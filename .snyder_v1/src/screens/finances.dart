import 'package:flutter/material.dart';
import '../db.dart';
import '../services/finance_engine.dart';
import '../theme.dart';
import '../widgets/common.dart';

class FinancesScreen extends StatefulWidget {
  const FinancesScreen({super.key, required this.token, required this.refresh, required this.openSettings});
  final int token;
  final VoidCallback refresh;
  final VoidCallback openSettings;
  @override
  State<FinancesScreen> createState() => _FinancesScreenState();
}

class _FinancesScreenState extends State<FinancesScreen> {
  int view = 0;

  @override
  Widget build(BuildContext context) {
    return SnyderPage(
      title: 'Finances',
      subtitle: 'Paychecks • Bills • Goals • Forecast',
      actions: [IconButton(onPressed: widget.openSettings, icon: const Icon(Icons.settings_outlined, color: SnyderColors.cyan))],
      child: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, icon: Icon(Icons.payments_outlined), label: Text('Paychecks')),
              ButtonSegment(value: 1, icon: Icon(Icons.receipt_long), label: Text('Bills')),
              ButtonSegment(value: 2, icon: Icon(Icons.savings_outlined), label: Text('Goals')),
              ButtonSegment(value: 3, icon: Icon(Icons.auto_graph), label: Text('Forecast')),
            ],
            selected: {view}, onSelectionChanged: (x) => setState(() => view = x.first),
          ),
        ),
        const SizedBox(height: 12),
        IndexedStack(index: view, children: [_paychecks(), _bills(), _goals(), _forecast()]),
      ]),
    );
  }

  Widget _paychecks() => FutureBuilder<Map<String, dynamic>>(
    key: ValueKey('pay-${widget.token}'),
    future: _loadPaychecks(),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final d = snap.data!;
      final history = d['history'] as List<Map<String, Object?>>;
      return Column(children: [
        SnyderCard(accent: SnyderColors.cyan, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sectionTitle(Icons.payments_outlined, 'Biweekly Paycheck Setup', trailing: IconButton(onPressed: () => _editIncome(d), icon: const Icon(Icons.edit_outlined))),
          const SizedBox(height: 8),
          Text(moneyFromCents(d['expected'] as int), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: SnyderColors.cyan)),
          Text('Expected take-home • next payday ${shortDate(d['payday'] as DateTime)}', style: const TextStyle(color: SnyderColors.muted)),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: _metric('Available cash', moneyFromCents(d['cash'] as int), SnyderColors.green)), Expanded(child: _metric('Household / flexible per check', moneyFromCents(d['buffer'] as int), SnyderColors.warning))]),
        ])),
        const SizedBox(height: 12),
        SnyderCard(child: Column(children: [
          sectionTitle(Icons.history, 'Paycheck History', trailing: IconButton(onPressed: _recordPaycheck, icon: const Icon(Icons.add))),
          if (history.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Record actual checks here when they arrive. Forecasting continues to use your expected amount.')),
          ...history.map((p) => ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.account_balance_wallet, color: SnyderColors.cyan), title: Text(shortDate(parseDate(p['pay_date']))), subtitle: Text(p['note'].toString()), trailing: Text(moneyFromCents((p['actual_cents'] ?? p['expected_cents']) as int), style: const TextStyle(fontWeight: FontWeight.w900)))),
        ])),
      ]);
    },
  );

  Future<Map<String, dynamic>> _loadPaychecks() async => {
    'expected': await AppDb.i.settingInt('expected_takehome_cents'),
    'payday': await FinanceEngine.nextPayday(),
    'cash': await AppDb.i.settingInt('available_cash_cents'),
    'buffer': await AppDb.i.settingInt('household_buffer_cents'),
    'history': await AppDb.i.rows('paycheck_history', orderBy: 'pay_date DESC, id DESC'),
  };

  Widget _bills() => FutureBuilder<List<BillAllocation>>(
    key: ValueKey('bills-${widget.token}'),
    future: FinanceEngine.billAllocations(),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final allocations = snap.data!;
      return SnyderCard(accent: SnyderColors.blue, child: Column(children: [
        sectionTitle(Icons.receipt_long, 'Bills & Sinking Funds', trailing: IconButton(onPressed: () => _billDialog(), icon: const Icon(Icons.add))),
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('The next-check amount is dynamic: remaining balance ÷ actual biweekly paychecks left before the due date.', style: TextStyle(color: SnyderColors.muted, fontSize: 12))),
        if (allocations.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Add your first bill.')),
        ...allocations.map((a) {
          final b = a.bill;
          final amount = b['amount_cents'] as int;
          final funded = b['funded_cents'] as int;
          final progress = amount <= 0 ? 0.0 : (funded / amount).clamp(0.0, 1.0).toDouble();
          return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(a.urgent ? Icons.warning_amber_rounded : Icons.receipt_long, color: a.urgent ? SnyderColors.warning : SnyderColors.cyan),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(b['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w900)), Text('${b['frequency']} • due ${shortDate(parseDate(b['next_due']))}', style: const TextStyle(color: SnyderColors.muted, fontSize: 11))])),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'fund') await _fundBill(b);
                  if (v == 'paid') { await FinanceEngine.markBillPaid(b); widget.refresh(); }
                  if (v == 'edit') await _billDialog(existing: b);
                  if (v == 'archive') { await AppDb.i.update('bills', {'active': 0}, b['id'] as int); widget.refresh(); }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'fund', child: Text('Add funded amount')),
                  PopupMenuItem(value: 'paid', child: Text('Mark bill paid / advance due date')),
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'archive', child: Text('Archive')),
                ],
              ),
            ]),
            const SizedBox(height: 5),
            LinearProgressIndicator(value: progress, minHeight: 7, borderRadius: BorderRadius.circular(99), color: SnyderColors.blue, backgroundColor: SnyderColors.line),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('${moneyFromCents(funded)} funded of ${moneyFromCents(amount)}', style: const TextStyle(color: SnyderColors.muted, fontSize: 11)), Text('Next check ${moneyFromCents(a.requiredCents)}', style: const TextStyle(color: SnyderColors.cyan, fontWeight: FontWeight.w900))]),
          ]));
        }),
      ]));
    },
  );

  Widget _goals() => FutureBuilder<List<Map<String, Object?>>>(
    key: ValueKey('goals-${widget.token}'),
    future: AppDb.i.rows('goals', where: 'active=1', orderBy: 'priority DESC, id ASC'),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final goals = snap.data!;
      return SnyderCard(accent: SnyderColors.violet, child: Column(children: [
        sectionTitle(Icons.savings_outlined, 'Savings Goals', trailing: IconButton(onPressed: () => _goalDialog(), icon: const Icon(Icons.add))),
        if (goals.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Add a goal and Snyder Family can plan it by deadline or fixed per-paycheck amount.')),
        ...goals.map((g) {
          final target = g['target_cents'] as int;
          final saved = g['saved_cents'] as int;
          final p = target <= 0 ? 0.0 : (saved / target).clamp(0.0, 1.0).toDouble();
          return Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(g['name'].toString().contains('Property') ? Icons.home_work_outlined : Icons.savings, color: g['name'].toString().contains('Property') ? SnyderColors.cyan : SnyderColors.violet),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(g['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w900)), Text(g['target_date']?.toString().isNotEmpty == true ? 'Target ${shortDate(parseDate(g['target_date']))}' : (g['per_paycheck_cents'] as int) > 0 ? '${moneyFromCents(g['per_paycheck_cents'] as int)} per paycheck' : 'No deadline / fixed contribution', style: const TextStyle(color: SnyderColors.muted, fontSize: 11))])),
              PopupMenuButton<String>(onSelected: (v) async {
                if (v == 'add') await _contributeGoal(g);
                if (v == 'edit') await _goalDialog(existing: g);
                if (v == 'archive') { await AppDb.i.update('goals', {'active': 0}, g['id'] as int); widget.refresh(); }
              }, itemBuilder: (_) => const [PopupMenuItem(value: 'add', child: Text('Add savings')), PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'archive', child: Text('Archive'))]),
            ]),
            const SizedBox(height: 5), LinearProgressIndicator(value: p, minHeight: 8, borderRadius: BorderRadius.circular(99), color: g['name'].toString().contains('Property') ? SnyderColors.cyan : SnyderColors.violet, backgroundColor: SnyderColors.line),
            const SizedBox(height: 4), Text('${moneyFromCents(saved)} / ${moneyFromCents(target)}', style: const TextStyle(color: SnyderColors.muted, fontSize: 11)),
          ]));
        }),
      ]));
    },
  );

  Widget _forecast() => FutureBuilder<PaycheckPlan>(
    key: ValueKey('forecast-${widget.token}'),
    future: FinanceEngine.planNextPaycheck(),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final plan = snap.data!;
      return Column(children: [
        SnyderCard(accent: SnyderColors.violet, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sectionTitle(Icons.auto_graph, 'Can We Afford It?'),
          const SizedBox(height: 8),
          const Text('Test a future purchase against expected income, due bills, savings commitments, and your per-paycheck household budget.'),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _affordabilityDialog, icon: const Icon(Icons.query_stats), label: const Text('Run purchase forecast'))),
        ])),
        const SizedBox(height: 12),
        SnyderCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sectionTitle(Icons.pie_chart, 'Next Check Plan'),
          _line('Expected take-home', plan.paycheckCents, SnyderColors.green),
          _line('Bills', -plan.totalBillsCents, SnyderColors.cyan),
          _line('Savings goals', -plan.goalCents, SnyderColors.violet),
          _line('Stockpile reserve', -plan.stockpileCents, SnyderColors.blue),
          _line('Household / flexible', -plan.householdBufferCents, SnyderColors.warning),
          const Divider(),
          _line('Left to assign', plan.leftCents, plan.leftCents >= 0 ? SnyderColors.green : SnyderColors.danger, bold: true),
        ])),
      ]);
    },
  );

  Widget _line(String label, int cents, Color color, {bool bold = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w500)), Text('${cents < 0 ? '−' : ''}${moneyFromCents(cents.abs())}', style: TextStyle(color: color, fontWeight: FontWeight.w900))]));
  Widget _metric(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: SnyderColors.muted, fontSize: 11)), Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 17))]);

  Future<void> _editIncome(Map<String, dynamic> d) async {
    final expected = TextEditingController(text: ((d['expected'] as int) / 100).toStringAsFixed(2));
    final cash = TextEditingController(text: ((d['cash'] as int) / 100).toStringAsFixed(2));
    final buffer = TextEditingController(text: ((d['buffer'] as int) / 100).toStringAsFixed(2));
    var payday = d['payday'] as DateTime;
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(title: const Text('Paycheck settings'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: expected, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Expected take-home', prefixText: r'$ ')), const SizedBox(height: 8),
      TextField(controller: cash, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Available cash for forecasts', prefixText: r'$ ')), const SizedBox(height: 8),
      TextField(controller: buffer, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Household / flexible per paycheck', prefixText: r'$ ')),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Next payday'), subtitle: Text(shortDate(payday)), onTap: () async { final x = await pickDate(context, payday); if (x != null) setDialog(() => payday = x); }),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save'))])));
    if (ok == true) {
      await AppDb.i.setSetting('expected_takehome_cents', centsFromText(expected.text));
      await AppDb.i.setSetting('available_cash_cents', centsFromText(cash.text));
      await AppDb.i.setSetting('household_buffer_cents', centsFromText(buffer.text));
      await AppDb.i.setSetting('next_payday', isoDate(payday));
      widget.refresh();
    }
  }

  Future<void> _recordPaycheck() async {
    final expected = await AppDb.i.settingInt('expected_takehome_cents');
    final actual = TextEditingController(text: (expected / 100).toStringAsFixed(2));
    final note = TextEditingController();
    var date = await FinanceEngine.nextPayday();
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(title: const Text('Record paycheck'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: actual, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Actual take-home', prefixText: r'$ ')), const SizedBox(height: 8), TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Pay date'), subtitle: Text(shortDate(date)), onTap: () async { final x = await pickDate(context, date); if (x != null) setDialog(() => date = x); }),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save'))])));
    if (ok == true) {
      await AppDb.i.insert('paycheck_history', {'pay_date': isoDate(date), 'expected_cents': expected, 'actual_cents': centsFromText(actual.text), 'note': note.text.trim(), 'created_at': AppDb.i.now()});
      final next = date.add(const Duration(days: 14));
      final currentNext = await FinanceEngine.nextPayday();
      if (!next.isBefore(currentNext)) await AppDb.i.setSetting('next_payday', isoDate(next));
      widget.refresh();
    }
  }

  Future<void> _billDialog({Map<String, Object?>? existing}) async {
    final name = TextEditingController(text: existing?['name']?.toString() ?? '');
    final amount = TextEditingController(text: existing == null ? '' : ((existing['amount_cents'] as int) / 100).toStringAsFixed(2));
    final funded = TextEditingController(text: existing == null ? '0' : ((existing['funded_cents'] as int) / 100).toStringAsFixed(2));
    final category = TextEditingController(text: existing?['category']?.toString() ?? 'Household');
    var due = existing == null ? DateTime.now().add(const Duration(days: 14)) : parseDate(existing['next_due']);
    var frequency = existing?['frequency']?.toString() ?? 'monthly';
    var autopay = (existing?['autopay'] as int? ?? 0) == 1;
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(title: Text(existing == null ? 'Add bill' : 'Edit bill'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Bill / sinking fund')), const SizedBox(height: 8),
      Row(children: [Expanded(child: TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount due', prefixText: r'$ '))), const SizedBox(width: 8), Expanded(child: TextField(controller: funded, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Already funded', prefixText: r'$ ')))]), const SizedBox(height: 8),
      TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')), const SizedBox(height: 8),
      DropdownButtonFormField<String>(initialValue: frequency, decoration: const InputDecoration(labelText: 'Frequency'), items: const [DropdownMenuItem(value: 'weekly', child: Text('Weekly')), DropdownMenuItem(value: 'biweekly', child: Text('Biweekly')), DropdownMenuItem(value: 'monthly', child: Text('Monthly')), DropdownMenuItem(value: 'quarterly', child: Text('Quarterly')), DropdownMenuItem(value: 'annual', child: Text('Annual'))], onChanged: (v) => setDialog(() => frequency = v ?? 'monthly')),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Next due date'), subtitle: Text(shortDate(due)), onTap: () async { final x = await pickDate(context, due); if (x != null) setDialog(() => due = x); }),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: autopay, onChanged: (v) => setDialog(() => autopay = v), title: const Text('Autopay')),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save'))])));
    if (ok == true && name.text.trim().isNotEmpty) {
      final row = {'name': name.text.trim(), 'amount_cents': centsFromText(amount.text), 'funded_cents': centsFromText(funded.text), 'next_due': isoDate(due), 'frequency': frequency, 'category': category.text.trim().isEmpty ? 'Household' : category.text.trim(), 'autopay': autopay ? 1 : 0, 'active': 1};
      if (existing == null) await AppDb.i.insert('bills', {...row, 'created_at': AppDb.i.now()}); else await AppDb.i.update('bills', row, existing['id'] as int);
      widget.refresh();
    }
  }

  Future<void> _fundBill(Map<String, Object?> bill) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text('Fund ${bill['name']}'), content: TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Add to funded bucket', prefixText: r'$ ')), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Add'))]));
    if (ok == true) {
      final next = (bill['funded_cents'] as int) + centsFromText(c.text);
      await AppDb.i.update('bills', {'funded_cents': next.clamp(0, bill['amount_cents'] as int)}, bill['id'] as int);
      widget.refresh();
    }
  }

  Future<void> _goalDialog({Map<String, Object?>? existing}) async {
    final name = TextEditingController(text: existing?['name']?.toString() ?? '');
    final target = TextEditingController(text: existing == null ? '' : ((existing['target_cents'] as int) / 100).toStringAsFixed(2));
    final saved = TextEditingController(text: existing == null ? '0' : ((existing['saved_cents'] as int) / 100).toStringAsFixed(2));
    final per = TextEditingController(text: existing == null ? '0' : ((existing['per_paycheck_cents'] as int) / 100).toStringAsFixed(2));
    final category = TextEditingController(text: existing?['category']?.toString() ?? 'Savings');
    DateTime? date = existing?['target_date']?.toString().isNotEmpty == true ? parseDate(existing!['target_date']) : null;
    var priority = existing?['priority'] as int? ?? 1;
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(title: Text(existing == null ? 'Add savings goal' : 'Edit savings goal'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Goal')), const SizedBox(height: 8),
      Row(children: [Expanded(child: TextField(controller: target, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Target', prefixText: r'$ '))), const SizedBox(width: 8), Expanded(child: TextField(controller: saved, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Saved', prefixText: r'$ ')))]), const SizedBox(height: 8),
      TextField(controller: per, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Fixed per paycheck (0 = calculate by deadline)', prefixText: r'$ ')), const SizedBox(height: 8),
      TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')), const SizedBox(height: 8),
      DropdownButtonFormField<int>(initialValue: priority, decoration: const InputDecoration(labelText: 'Priority'), items: const [DropdownMenuItem(value: 1, child: Text('Normal')), DropdownMenuItem(value: 2, child: Text('High')), DropdownMenuItem(value: 3, child: Text('Top priority'))], onChanged: (v) => setDialog(() => priority = v ?? 1)),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Target date'), subtitle: Text(date == null ? 'No deadline' : shortDate(date!)), trailing: Row(mainAxisSize: MainAxisSize.min, children: [if (date != null) IconButton(onPressed: () => setDialog(() => date = null), icon: const Icon(Icons.clear)), const Icon(Icons.calendar_month)]), onTap: () async { final x = await pickDate(context, date ?? DateTime.now().add(const Duration(days: 180))); if (x != null) setDialog(() => date = x); }),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save'))])));
    if (ok == true && name.text.trim().isNotEmpty) {
      final row = {'name': name.text.trim(), 'target_cents': centsFromText(target.text), 'saved_cents': centsFromText(saved.text), 'target_date': date == null ? null : isoDate(date!), 'per_paycheck_cents': centsFromText(per.text), 'priority': priority, 'category': category.text.trim().isEmpty ? 'Savings' : category.text.trim(), 'active': 1};
      if (existing == null) await AppDb.i.insert('goals', {...row, 'created_at': AppDb.i.now()}); else await AppDb.i.update('goals', row, existing['id'] as int);
      widget.refresh();
    }
  }

  Future<void> _contributeGoal(Map<String, Object?> g) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text('Add to ${g['name']}'), content: TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Contribution', prefixText: r'$ ')), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Add'))]));
    if (ok == true) {
      final next = (g['saved_cents'] as int) + centsFromText(c.text);
      await AppDb.i.update('goals', {'saved_cents': next.clamp(0, g['target_cents'] as int)}, g['id'] as int);
      widget.refresh();
    }
  }

  Future<void> _affordabilityDialog() async {
    final amount = TextEditingController();
    var date = DateTime.now();
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(title: const Text('Can We Afford It?'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Purchase amount', prefixText: r'$ ')), ListTile(contentPadding: EdgeInsets.zero, title: const Text('Purchase date'), subtitle: Text(shortDate(date)), onTap: () async { final x = await pickDate(context, date); if (x != null) setDialog(() => date = x); })]), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Run Forecast'))])));
    if (ok != true || !mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    final result = await FinanceEngine.canAfford(centsFromText(amount.text), date);
    if (!mounted) return;
    Navigator.pop(context);
    await showDialog<void>(context: context, builder: (d) => AlertDialog(title: Row(children: [Icon(result.safe ? Icons.check_circle : Icons.warning_amber_rounded, color: result.safe ? SnyderColors.green : SnyderColors.warning), const SizedBox(width: 8), Text(result.safe ? 'YES — SAFE' : 'NOT YET')]), content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Purchase: ${moneyFromCents(result.purchaseCents)} on ${shortDate(result.purchaseDate)}'), const SizedBox(height: 10),
      _line('Future income', result.incomeCents, SnyderColors.green), _line('Bills', -result.requiredBillsCents, SnyderColors.cyan), _line('Savings commitments', -result.requiredGoalsCents, SnyderColors.violet), _line('Household budget', -result.householdCents, SnyderColors.warning), const Divider(), _line('Projected after purchase', result.projectedCents, result.projectedCents >= 0 ? SnyderColors.green : SnyderColors.danger, bold: true),
      if (!result.safe && result.earliestSafeDate != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Earliest projected safe date: ${shortDate(result.earliestSafeDate!)}', style: const TextStyle(color: SnyderColors.cyan, fontWeight: FontWeight.w900))),
    ]), actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Done'))]));
  }
}