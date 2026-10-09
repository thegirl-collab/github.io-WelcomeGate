import 'dart:math' as math;
import '../db.dart';
import '../widgets/common.dart';

class BillAllocation {
  BillAllocation({required this.bill, required this.requiredCents, required this.paychecksRemaining, required this.urgent});
  final Map<String, Object?> bill;
  final int requiredCents;
  final int paychecksRemaining;
  final bool urgent;
}

class PaycheckPlan {
  PaycheckPlan({
    required this.paycheckCents,
    required this.billAllocations,
    required this.totalBillsCents,
    required this.goalCents,
    required this.stockpileCents,
    required this.householdBufferCents,
    required this.leftCents,
  });
  final int paycheckCents;
  final List<BillAllocation> billAllocations;
  final int totalBillsCents;
  final int goalCents;
  final int stockpileCents;
  final int householdBufferCents;
  final int leftCents;
}

class AffordabilityResult {
  AffordabilityResult({
    required this.safe,
    required this.purchaseCents,
    required this.purchaseDate,
    required this.projectedCents,
    required this.requiredBillsCents,
    required this.requiredGoalsCents,
    required this.householdCents,
    required this.incomeCents,
    this.earliestSafeDate,
  });
  final bool safe;
  final int purchaseCents;
  final DateTime purchaseDate;
  final int projectedCents;
  final int requiredBillsCents;
  final int requiredGoalsCents;
  final int householdCents;
  final int incomeCents;
  final DateTime? earliestSafeDate;
}

class FinanceEngine {
  static Future<DateTime> nextPayday() async => parseDate(await AppDb.i.setting('next_payday'));
  static Future<int> frequencyDays() async => AppDb.i.settingInt('pay_frequency_days', fallback: 14);

  static int paycheckCountThrough(DateTime fromPayday, DateTime through, int frequencyDays) {
    final start = DateTime(fromPayday.year, fromPayday.month, fromPayday.day);
    final end = DateTime(through.year, through.month, through.day);
    if (end.isBefore(start)) return 0;
    return (end.difference(start).inDays ~/ frequencyDays) + 1;
  }

  static DateTime paydayAt(DateTime first, int index, int frequencyDays) => first.add(Duration(days: frequencyDays * index));

  static Future<List<BillAllocation>> billAllocations({DateTime? planPayday}) async {
    final db = AppDb.i;
    final payday = planPayday ?? await nextPayday();
    final freq = await frequencyDays();
    final bills = await db.rows('bills', where: 'active=1', orderBy: 'next_due ASC');
    final out = <BillAllocation>[];
    final today = DateTime.now();
    for (final b in bills) {
      final due = parseDate(b['next_due']);
      final remaining = math.max(0, (b['amount_cents'] as int) - (b['funded_cents'] as int));
      var count = paycheckCountThrough(payday, due, freq);
      final urgent = due.isBefore(payday) || due.isBefore(today);
      if (count < 1) count = 1;
      final required = remaining <= 0 ? 0 : (remaining / count).ceil();
      out.add(BillAllocation(bill: b, requiredCents: required, paychecksRemaining: count, urgent: urgent));
    }
    return out;
  }

  static Future<int> plannedGoalContributionForPaycheck(DateTime payday) async {
    final db = AppDb.i;
    final freq = await frequencyDays();
    final goals = await db.rows('goals', where: 'active=1', orderBy: 'priority DESC, id ASC');
    var total = 0;
    for (final g in goals) {
      final target = g['target_cents'] as int;
      final saved = g['saved_cents'] as int;
      final remaining = math.max(0, target - saved);
      if (remaining == 0) continue;
      final fixed = g['per_paycheck_cents'] as int;
      if (fixed > 0) {
        total += math.min(fixed, remaining);
        continue;
      }
      final dateRaw = g['target_date']?.toString();
      if (dateRaw != null && dateRaw.isNotEmpty) {
        final targetDate = parseDate(dateRaw);
        var count = paycheckCountThrough(payday, targetDate, freq);
        if (count < 1) count = 1;
        total += (remaining / count).ceil();
      }
    }
    return total;
  }

  static Future<int> annualStockpileRemainingCents() async {
    final items = await AppDb.i.rows('stock_items', where: 'active=1');
    var total = 0;
    for (final i in items) {
      final annual = (i['annual_need'] as num).toDouble();
      final reserve = (i['reserve_qty'] as num).toDouble();
      final onHand = (i['on_hand'] as num).toDouble();
      final pack = math.max(.0001, (i['package_qty'] as num).toDouble());
      final cost = i['package_cost_cents'] as int;
      final neededUnits = math.max(0.0, annual + reserve - onHand);
      final packages = (neededUnits / pack).ceil();
      total += packages * cost;
    }
    return total;
  }

  static Future<PaycheckPlan> planNextPaycheck() async {
    final db = AppDb.i;
    final paycheck = await db.settingInt('expected_takehome_cents');
    final payday = await nextPayday();
    final bills = await billAllocations(planPayday: payday);
    final billTotal = bills.fold<int>(0, (s, x) => s + x.requiredCents);
    final goals = await plannedGoalContributionForPaycheck(payday);
    final stockAnnual = await annualStockpileRemainingCents();
    final stockBudget = math.min((paycheck * .18).round(), (stockAnnual / 26).ceil());
    final household = await db.settingInt('household_buffer_cents');
    return PaycheckPlan(
      paycheckCents: paycheck,
      billAllocations: bills,
      totalBillsCents: billTotal,
      goalCents: goals,
      stockpileCents: stockBudget,
      householdBufferCents: household,
      leftCents: paycheck - billTotal - goals - stockBudget - household,
    );
  }

  static DateTime advanceDue(DateTime due, String frequency) {
    switch (frequency) {
      case 'weekly':
        return due.add(const Duration(days: 7));
      case 'biweekly':
        return due.add(const Duration(days: 14));
      case 'quarterly':
        return DateTime(due.year, due.month + 3, due.day);
      case 'annual':
        return DateTime(due.year + 1, due.month, due.day);
      case 'monthly':
      default:
        return DateTime(due.year, due.month + 1, due.day);
    }
  }

  static Future<void> markBillPaid(Map<String, Object?> bill) async {
    final due = parseDate(bill['next_due']);
    final next = advanceDue(due, bill['frequency'].toString());
    await AppDb.i.update('bills', {'funded_cents': 0, 'next_due': isoDate(next)}, bill['id'] as int);
  }

  static Future<int> incomeThrough(DateTime date) async {
    final db = AppDb.i;
    final first = await nextPayday();
    final freq = await frequencyDays();
    final expected = await db.settingInt('expected_takehome_cents');
    final count = paycheckCountThrough(first, date, freq);
    return count * expected;
  }

  static Future<int> billObligationsThrough(DateTime date) async {
    final bills = await AppDb.i.rows('bills', where: 'active=1');
    var total = 0;
    final today = DateTime.now();
    for (final b in bills) {
      var due = parseDate(b['next_due']);
      var funded = b['funded_cents'] as int;
      final amount = b['amount_cents'] as int;
      var first = true;
      while (!due.isAfter(date)) {
        if (!due.isBefore(DateTime(today.year, today.month, today.day))) {
          total += math.max(0, amount - (first ? funded : 0));
        }
        first = false;
        due = advanceDue(due, b['frequency'].toString());
      }
    }
    return total;
  }

  static Future<int> goalObligationsThrough(DateTime date) async {
    final db = AppDb.i;
    final first = await nextPayday();
    final freq = await frequencyDays();
    final goals = await db.rows('goals', where: 'active=1');
    var total = 0;
    for (final g in goals) {
      final remaining = math.max(0, (g['target_cents'] as int) - (g['saved_cents'] as int));
      if (remaining == 0) continue;
      final fixed = g['per_paycheck_cents'] as int;
      final checkCount = paycheckCountThrough(first, date, freq);
      if (fixed > 0) {
        total += math.min(remaining, fixed * checkCount);
      } else {
        final raw = g['target_date']?.toString() ?? '';
        if (raw.isNotEmpty) {
          final target = parseDate(raw);
          final horizon = target.isBefore(date) ? target : date;
          final totalChecksToTarget = math.max(1, paycheckCountThrough(first, target, freq));
          final per = (remaining / totalChecksToTarget).ceil();
          total += math.min(remaining, per * paycheckCountThrough(first, horizon, freq));
        }
      }
    }
    return total;
  }

  static Future<AffordabilityResult> canAfford(int purchaseCents, DateTime date, {bool findEarliest = true}) async {
    final db = AppDb.i;
    final cash = await db.settingInt('available_cash_cents');
    final income = await incomeThrough(date);
    final bills = await billObligationsThrough(date);
    final goals = await goalObligationsThrough(date);
    final first = await nextPayday();
    final freq = await frequencyDays();
    final householdPerCheck = await db.settingInt('household_buffer_cents');
    final household = paycheckCountThrough(first, date, freq) * householdPerCheck;
    final projected = cash + income - bills - goals - household - purchaseCents;
    DateTime? earliest;
    if (findEarliest && projected < 0) {
      for (var days = 1; days <= 365; days++) {
        final candidate = date.add(Duration(days: days));
        final r = await canAfford(purchaseCents, candidate, findEarliest: false);
        if (r.safe) {
          earliest = candidate;
          break;
        }
      }
    }
    return AffordabilityResult(
      safe: projected >= 0,
      purchaseCents: purchaseCents,
      purchaseDate: date,
      projectedCents: projected,
      requiredBillsCents: bills,
      requiredGoalsCents: goals,
      householdCents: household,
      incomeCents: income,
      earliestSafeDate: earliest,
    );
  }

  static Future<Map<String, int>> monthlyOverview(DateTime month) async {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final payday = await nextPayday();
    final freq = await frequencyDays();
    final expected = await AppDb.i.settingInt('expected_takehome_cents');
    var income = 0;
    var p = payday;
    while (p.isBefore(first)) {
      p = p.add(Duration(days: freq));
    }
    while (!p.isAfter(last)) {
      income += expected;
      p = p.add(Duration(days: freq));
    }
    final bills = await AppDb.i.rows('bills', where: 'active=1');
    var expenses = 0;
    for (final b in bills) {
      var due = parseDate(b['next_due']);
      while (due.isBefore(first)) {
        due = advanceDue(due, b['frequency'].toString());
      }
      while (!due.isAfter(last)) {
        expenses += b['amount_cents'] as int;
        due = advanceDue(due, b['frequency'].toString());
      }
    }
    final buffer = await AppDb.i.settingInt('household_buffer_cents');
    var checks = 0;
    p = payday;
    while (p.isBefore(first)) p = p.add(Duration(days: freq));
    while (!p.isAfter(last)) { checks++; p = p.add(Duration(days: freq)); }
    expenses += checks * buffer;
    return {'income': income, 'expenses': expenses, 'remaining': income - expenses};
  }
}