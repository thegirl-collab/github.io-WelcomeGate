import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../db.dart';
import '../services/finance_engine.dart';
import '../services/property_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.token, required this.refresh, required this.openSettings});
  final int token;
  final VoidCallback refresh;
  final VoidCallback openSettings;

  Future<Map<String, dynamic>> load() async {
    final db = AppDb.i;
    final plan = await FinanceEngine.planNextPaycheck();
    final payday = await FinanceEngine.nextPayday();
    final goals = await db.rows('goals', where: 'active=1', orderBy: 'priority DESC, id ASC');
    final stock = await db.rows('stock_items', where: 'active=1', orderBy: 'name ASC');
    final shopping = await db.rows('shopping_items', where: 'checked=0', orderBy: 'created_at ASC');
    final tasks = await db.rows('tasks', where: 'done=0', orderBy: 'due_date ASC, id ASC');
    final homeGoals = await db.rows('home_goals', where: 'done=0', orderBy: 'id ASC');
    final monthly = await FinanceEngine.monthlyOverview(DateTime.now());
    final properties = await PropertyService.properties();
    Map<String, dynamic>? property;
    if (properties.isNotEmpty) {
      final p = properties.first;
      final pid = p['id'] as int;
      await PropertyService.postChargesThroughToday(pid);
      property = {
        'profile': p,
        'balance': await PropertyService.balance(pid),
        'cashflow': await PropertyService.rentCashFlow(pid, year: DateTime.now().year),
      };
    }
    return {
      'display': await db.setting('display_name', fallback: 'Cyn'),
      'household': await db.setting('household_name', fallback: 'Snyder Family'),
      'plan': plan,
      'payday': payday,
      'goals': goals,
      'stock': stock,
      'shopping': shopping,
      'tasks': tasks,
      'home_goals': homeGoals,
      'monthly': monthly,
      'property': property,
    };
  }

  @override
  Widget build(BuildContext context) {
    return SnyderPage(
      title: 'Snyder Family',
      subtitle: "Cyn's private home command center",
      actions: [IconButton(onPressed: openSettings, icon: const Icon(Icons.settings_outlined, color: SnyderColors.cyan))],
      child: FutureBuilder<Map<String, dynamic>>(
        key: ValueKey(token),
        future: load(),
        builder: (context, snap) {
          if (!snap.hasData) return const Padding(padding: EdgeInsets.all(42), child: Center(child: CircularProgressIndicator()));
          final d = snap.data!;
          final plan = d['plan'] as PaycheckPlan;
          final payday = d['payday'] as DateTime;
          final goals = d['goals'] as List<Map<String, Object?>>;
          final stock = d['stock'] as List<Map<String, Object?>>;
          final shopping = d['shopping'] as List<Map<String, Object?>>;
          final tasks = d['tasks'] as List<Map<String, Object?>>;
          final monthly = d['monthly'] as Map<String, int>;
          final property = d['property'] as Map<String, dynamic>?;
          final days = payday.difference(DateTime.now()).inDays;
          final stockCost = stock.fold<int>(0, (sum, i) {
            final annual = (i['annual_need'] as num).toDouble();
            final reserve = (i['reserve_qty'] as num).toDouble();
            final onHand = (i['on_hand'] as num).toDouble();
            final pack = math.max(.0001, (i['package_qty'] as num).toDouble());
            final packages = (math.max(0.0, annual + reserve - onHand) / pack).ceil();
            return sum + packages * (i['package_cost_cents'] as int);
          });
          return Column(
            children: [
              SnyderCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  sectionTitle(Icons.calendar_month, 'Next Paycheck', trailing: IconButton(onPressed: () => _editPaycheck(context, plan.paycheckCents, payday), icon: const Icon(Icons.edit_outlined))),
                  Text(moneyFromCents(plan.paycheckCents), style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: SnyderColors.cyan)),
                  Text('${shortDate(payday)} • ${days <= 0 ? 'due now' : '$days days remaining'}', style: const TextStyle(color: SnyderColors.muted)),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: .67, minHeight: 8, borderRadius: BorderRadius.circular(99), color: SnyderColors.cyan, backgroundColor: SnyderColors.line),
                  const SizedBox(height: 9),
                  Text(plan.leftCents >= 0 ? '${moneyFromCents(plan.leftCents)} flexible after planned allocations' : '${moneyFromCents(plan.leftCents.abs())} over planned paycheck', style: TextStyle(color: plan.leftCents >= 0 ? SnyderColors.green : SnyderColors.danger, fontWeight: FontWeight.w800)),
                ]),
              ),
              const SizedBox(height: 12),
              SnyderCard(
                accent: SnyderColors.blue,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  sectionTitle(Icons.receipt_long, 'Bills to Fund'),
                  if (plan.billAllocations.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No bills yet. Add bills in Finances.', style: TextStyle(color: SnyderColors.muted))),
                  ...plan.billAllocations.take(6).map((a) {
                    final b = a.bill;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(a.urgent ? Icons.warning_amber_rounded : Icons.payments_outlined, color: a.urgent ? SnyderColors.warning : SnyderColors.cyan),
                      title: Text(b['name'].toString()),
                      subtitle: Text('Due ${shortDate(parseDate(b['next_due']))} • ${a.paychecksRemaining} check${a.paychecksRemaining == 1 ? '' : 's'} left'),
                      trailing: Text(moneyFromCents(a.requiredCents), style: const TextStyle(fontWeight: FontWeight.w900)),
                    );
                  }),
                  const Divider(),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('This paycheck for bills', style: TextStyle(color: SnyderColors.muted)), Text(moneyFromCents(plan.totalBillsCents), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: SnyderColors.cyan))]),
                ]),
              ),
              const SizedBox(height: 12),
              SnyderCard(
                accent: SnyderColors.violet,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  sectionTitle(Icons.pie_chart_outline, 'Smart Split • Paycheck Plan'),
                  _split('Bills', plan.totalBillsCents, plan.paycheckCents, SnyderColors.cyan),
                  _split('Savings goals', plan.goalCents, plan.paycheckCents, SnyderColors.violet),
                  _split('Yearly stockpile', plan.stockpileCents, plan.paycheckCents, SnyderColors.blue),
                  _split('Household / flexible', plan.householdBufferCents, plan.paycheckCents, SnyderColors.warning),
                  const Divider(),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Left to assign', style: TextStyle(color: SnyderColors.muted)), Text(moneyFromCents(plan.leftCents), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: plan.leftCents >= 0 ? SnyderColors.green : SnyderColors.danger))]),
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => _canAfford(context), icon: const Icon(Icons.auto_graph), label: const Text('Can We Afford It?'))),
                ]),
              ),
              const SizedBox(height: 12),
              SnyderCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  sectionTitle(Icons.inventory_2_outlined, 'Stockpile / Shopping'),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _metric('Annual stock still needed', moneyFromCents(stockCost), SnyderColors.cyan)),
                    Expanded(child: _metric('Shopping list', '${shopping.length} open', SnyderColors.violet)),
                  ]),
                  if (shopping.isNotEmpty) ...shopping.take(4).map((s) => ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: Icon(s['name'].toString().toLowerCase().contains('crow') ? Icons.flutter_dash : Icons.shopping_cart_outlined, color: SnyderColors.cyan), title: Text(s['name'].toString()), trailing: Text('${(s['qty'] as num).toStringAsFixed(1)}×'))),
                ]),
              ),
              const SizedBox(height: 12),
              SnyderCard(
                accent: SnyderColors.violet,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  sectionTitle(Icons.savings_outlined, 'Savings Goals'),
                  if (goals.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No savings goals yet. Add them in Finances.', style: TextStyle(color: SnyderColors.muted))),
                  ...goals.take(5).map((g) {
                    final target = g['target_cents'] as int;
                    final saved = g['saved_cents'] as int;
                    final progress = target <= 0 ? 0.0 : (saved / target).clamp(0.0, 1.0).toDouble();
                    return Padding(
                      padding: const EdgeInsets.only(top: 11),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [Expanded(child: Text(g['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w800))), Text('${moneyFromCents(saved)} / ${moneyFromCents(target)}', style: const TextStyle(fontSize: 11, color: SnyderColors.muted))]),
                        const SizedBox(height: 5),
                        LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(99), color: g['name'].toString().contains('Property') ? SnyderColors.cyan : SnyderColors.violet, backgroundColor: SnyderColors.line),
                      ]),
                    );
                  }),
                ]),
              ),
              const SizedBox(height: 12),
              SnyderCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  sectionTitle(Icons.task_alt, 'Household Tasks'),
                  if (tasks.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Nothing waiting. ✨', style: TextStyle(color: SnyderColors.green))),
                  ...tasks.take(6).map((t) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    title: Text(t['name'].toString()),
                    subtitle: Text(t['due_date']?.toString().isNotEmpty == true ? shortDate(parseDate(t['due_date'])) : t['due_label'].toString()),
                    onChanged: (_) async {
                      await AppDb.i.update('tasks', {'done': 1, 'completed_at': AppDb.i.now()}, t['id'] as int);
                      refresh();
                    },
                  )),
                ]),
              ),
              const SizedBox(height: 12),
              SnyderCard(
                accent: SnyderColors.blue,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  sectionTitle(Icons.bar_chart, 'Monthly Overview'),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _metric('Income', moneyFromCents(monthly['income'] ?? 0), SnyderColors.green)),
                    Expanded(child: _metric('Expenses', moneyFromCents(monthly['expenses'] ?? 0), SnyderColors.danger)),
                    Expanded(child: _metric('Remaining', moneyFromCents(monthly['remaining'] ?? 0), SnyderColors.cyan)),
                  ]),
                ]),
              ),
              if (property != null) ...[
                const SizedBox(height: 12),
                SnyderCard(
                  accent: SnyderColors.violet,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    sectionTitle(Icons.key_outlined, 'Property Hub Snapshot'),
                    const SizedBox(height: 8),
                    Text((property['profile'] as Map)['label'].toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _metric('Tenant balance', moneyFromCents(property['balance'] as int), (property['balance'] as int) > 0 ? SnyderColors.warning : SnyderColors.green)),
                      Expanded(child: _metric('YTD property cash flow', moneyFromCents(property['cashflow'] as int), (property['cashflow'] as int) >= 0 ? SnyderColors.green : SnyderColors.danger)),
                    ]),
                  ]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _split(String label, int amount, int total, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(width: 145, child: Text(label)),
          Expanded(child: LinearProgressIndicator(value: total <= 0 ? 0 : (amount / total).clamp(0.0, 1.0).toDouble(), minHeight: 8, borderRadius: BorderRadius.circular(99), color: color, backgroundColor: SnyderColors.line)),
          const SizedBox(width: 8),
          SizedBox(width: 84, child: Text(moneyFromCents(amount), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
      );

  Widget _metric(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: SnyderColors.muted, fontSize: 11)),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
      ]);

  Future<void> _editPaycheck(BuildContext context, int cents, DateTime payday) async {
    final amount = TextEditingController(text: (cents / 100).toStringAsFixed(2));
    var date = payday;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
        title: const Text('Next paycheck'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Expected take-home', prefixText: r'$ ')),
          const SizedBox(height: 8),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Payday'), subtitle: Text(shortDate(date)), onTap: () async { final d = await pickDate(context, date); if (d != null) setDialog(() => date = d); }),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save'))],
      )),
    );
    if (ok == true) {
      await AppDb.i.setSetting('expected_takehome_cents', centsFromText(amount.text));
      await AppDb.i.setSetting('next_payday', isoDate(date));
      refresh();
    }
  }

  Future<void> _canAfford(BuildContext context) async {
    final amount = TextEditingController();
    var date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
        title: const Text('Can We Afford It?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Purchase amount', prefixText: r'$ ')),
          const SizedBox(height: 8),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Purchase date'), subtitle: Text(shortDate(date)), onTap: () async { final d = await pickDate(context, date); if (d != null) setDialog(() => date = d); }),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Run Forecast'))],
      )),
    );
    if (ok != true || !context.mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    final result = await FinanceEngine.canAfford(centsFromText(amount.text), date);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: Row(children: [Icon(result.safe ? Icons.check_circle : Icons.warning_amber_rounded, color: result.safe ? SnyderColors.green : SnyderColors.warning), const SizedBox(width: 8), Text(result.safe ? 'YES — SAFE' : 'NOT YET')]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(result.safe ? 'After the purchase, the current forecast remains above zero.' : 'This purchase would push the current forecast below zero.', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text('Income through date: ${moneyFromCents(result.incomeCents)}'),
        Text('Bills through date: ${moneyFromCents(result.requiredBillsCents)}'),
        Text('Goal contributions: ${moneyFromCents(result.requiredGoalsCents)}'),
        Text('Household budget: ${moneyFromCents(result.householdCents)}'),
        const Divider(),
        Text('Projected after purchase: ${moneyFromCents(result.projectedCents)}', style: TextStyle(fontWeight: FontWeight.w900, color: result.projectedCents >= 0 ? SnyderColors.green : SnyderColors.danger)),
        if (!result.safe && result.earliestSafeDate != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Earliest projected safe date: ${shortDate(result.earliestSafeDate!)}', style: const TextStyle(color: SnyderColors.cyan, fontWeight: FontWeight.w800))),
      ]),
      actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Got it'))],
    ));
  }
}