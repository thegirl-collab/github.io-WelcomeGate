import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../db.dart';
import '../services/finance_engine.dart';
import '../theme.dart';
import '../widgets/common.dart';

class StockpileScreen extends StatefulWidget {
  const StockpileScreen({super.key, required this.token, required this.refresh, required this.openSettings});
  final int token;
  final VoidCallback refresh;
  final VoidCallback openSettings;
  @override
  State<StockpileScreen> createState() => _StockpileScreenState();
}

class _StockpileScreenState extends State<StockpileScreen> {
  int view = 0;

  @override
  Widget build(BuildContext context) {
    return SnyderPage(
      title: 'Stockpile',
      subtitle: 'Shopping • Inventory • Yearly bulk plan',
      actions: [IconButton(onPressed: widget.openSettings, icon: const Icon(Icons.settings_outlined, color: SnyderColors.cyan))],
      child: Column(children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, icon: Icon(Icons.shopping_cart_outlined), label: Text('Shopping')),
            ButtonSegment(value: 1, icon: Icon(Icons.inventory_2_outlined), label: Text('Inventory')),
            ButtonSegment(value: 2, icon: Icon(Icons.calendar_view_month), label: Text('Bulk Plan')),
          ],
          selected: {view}, onSelectionChanged: (x) => setState(() => view = x.first),
        ),
        const SizedBox(height: 12),
        IndexedStack(index: view, children: [_shopping(), _inventory(), _bulk()]),
      ]),
    );
  }

  Widget _shopping() => FutureBuilder<List<Map<String, Object?>>>(
    key: ValueKey('shop-${widget.token}'),
    future: AppDb.i.rows('shopping_items', orderBy: 'checked ASC, category ASC, id ASC'),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final items = snap.data!;
      final open = items.where((x) => (x['checked'] as int) == 0).toList();
      final total = open.fold<int>(0, (s, x) => s + (x['estimated_cents'] as int));
      return SnyderCard(child: Column(children: [
        sectionTitle(Icons.shopping_cart_outlined, 'Shopping List', trailing: IconButton(onPressed: () => _shoppingDialog(), icon: const Icon(Icons.add))),
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('${open.length} open items', style: const TextStyle(color: SnyderColors.muted)), Text('Estimated ${moneyFromCents(total)}', style: const TextStyle(color: SnyderColors.cyan, fontWeight: FontWeight.w900))])),
        if (items.isEmpty) const Padding(padding: EdgeInsets.all(18), child: Text('Your list is clear. Add what the house needs.')),
        ...items.map((x) {
          final checked = (x['checked'] as int) == 1;
          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: checked,
            title: Text(x['name'].toString(), style: TextStyle(decoration: checked ? TextDecoration.lineThrough : null)),
            subtitle: Text('${x['category']} • Qty ${(x['qty'] as num).toStringAsFixed(1)}${(x['estimated_cents'] as int) > 0 ? ' • ${moneyFromCents(x['estimated_cents'] as int)}' : ''}'),
            secondary: Icon(x['name'].toString().toLowerCase().contains('crow') ? Icons.flutter_dash : Icons.shopping_bag_outlined, color: x['name'].toString().toLowerCase().contains('crow') ? SnyderColors.violet : SnyderColors.cyan),
            onChanged: (_) => _toggleShopping(x),
            controlAffinity: ListTileControlAffinity.trailing,
          );
        }),
      ]));
    },
  );

  Widget _inventory() => FutureBuilder<List<Map<String, Object?>>>(
    key: ValueKey('inv-${widget.token}'),
    future: AppDb.i.rows('stock_items', where: 'active=1', orderBy: 'category ASC, name ASC'),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final items = snap.data!;
      return SnyderCard(accent: SnyderColors.violet, child: Column(children: [
        sectionTitle(Icons.inventory_2_outlined, 'Household Inventory', trailing: IconButton(onPressed: () => _stockDialog(), icon: const Icon(Icons.add))),
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Track what you own, how much the family uses in a year, reserve level, package size, cost, store, and reorder point.', style: TextStyle(color: SnyderColors.muted, fontSize: 12))),
        if (items.isEmpty) const Padding(padding: EdgeInsets.all(18), child: Text('No stockpile items yet.')),
        ...items.map((x) {
          final onHand = (x['on_hand'] as num).toDouble();
          final reorder = (x['reorder_point'] as num).toDouble();
          final low = reorder > 0 && onHand <= reorder;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(backgroundColor: (low ? SnyderColors.warning : SnyderColors.cyan).withValues(alpha: .12), child: Icon(low ? Icons.warning_amber_rounded : Icons.inventory_2, color: low ? SnyderColors.warning : SnyderColors.cyan)),
            title: Text(x['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${x['category']} • On hand ${onHand.toStringAsFixed(1)} • Annual ${(x['annual_need'] as num).toStringAsFixed(1)}${x['preferred_store'].toString().isNotEmpty ? ' • ${x['preferred_store']}' : ''}'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') await _stockDialog(existing: x);
                if (v == 'shop') await _addStockToShopping(x);
                if (v == 'delete') { await AppDb.i.update('stock_items', {'active': 0}, x['id'] as int); widget.refresh(); }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'shop', child: Text('Add to shopping')), PopupMenuItem(value: 'delete', child: Text('Archive'))],
            ),
          );
        }),
      ]));
    },
  );

  Widget _bulk() => FutureBuilder<List<Map<String, Object?>>>(
    key: ValueKey('bulk-${widget.token}'),
    future: AppDb.i.rows('stock_items', where: 'active=1', orderBy: 'category ASC, name ASC'),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final items = snap.data!;
      return FutureBuilder<int>(future: FinanceEngine.annualStockpileRemainingCents(), builder: (context, costSnap) {
        final total = costSnap.data ?? 0;
        return Column(children: [
          SnyderCard(accent: SnyderColors.blue, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            sectionTitle(Icons.calendar_view_month, 'Yearly Bulk Plan'),
            const SizedBox(height: 8),
            Text(moneyFromCents(total), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: SnyderColors.cyan)),
            const Text('estimated remaining yearly stockpile cost based on your package sizes and prices', style: TextStyle(color: SnyderColors.muted)),
          ])),
          const SizedBox(height: 12),
          SnyderCard(child: Column(children: items.map((x) {
            final annual = (x['annual_need'] as num).toDouble();
            final reserve = (x['reserve_qty'] as num).toDouble();
            final onHand = (x['on_hand'] as num).toDouble();
            final pack = math.max(.0001, (x['package_qty'] as num).toDouble());
            final needed = math.max(0.0, annual + reserve - onHand);
            final packages = (needed / pack).ceil();
            final cost = packages * (x['package_cost_cents'] as int);
            final reorder = (x['reorder_point'] as num).toDouble();
            final status = onHand <= reorder && reorder > 0 ? 'BUY NOW' : packages == 0 ? 'SET FOR YEAR' : 'PLANNED';
            final statusColor = status == 'BUY NOW' ? SnyderColors.warning : status == 'SET FOR YEAR' ? SnyderColors.green : SnyderColors.cyan;
            return Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(x['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w800))), Text(status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w900))]),
              const SizedBox(height: 3),
              Text('Need ${needed.toStringAsFixed(1)} units • $packages package${packages == 1 ? '' : 's'} • ${moneyFromCents(cost)}', style: const TextStyle(color: SnyderColors.muted)),
              if (packages > 0) Padding(padding: const EdgeInsets.only(top: 6), child: SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => _addStockToShopping(x, suggestedPackages: packages), icon: const Icon(Icons.add_shopping_cart), label: const Text('Add suggested bulk buy to shopping')))),
            ]));
          }).toList()))
        ]);
      });
    },
  );

  Future<void> _toggleShopping(Map<String, Object?> row) async {
    final checked = (row['checked'] as int) == 1;
    if (!checked && row['stock_item_id'] != null) {
      final stock = await AppDb.i.one('stock_items', row['stock_item_id'] as int);
      if (stock != null) {
        final boughtUnits = (row['qty'] as num).toDouble() * (stock['package_qty'] as num).toDouble();
        final newQty = (stock['on_hand'] as num).toDouble() + boughtUnits;
        await AppDb.i.update('stock_items', {'on_hand': newQty}, stock['id'] as int);
      }
    }
    await AppDb.i.update('shopping_items', {'checked': checked ? 0 : 1}, row['id'] as int);
    widget.refresh();
  }

  Future<void> _shoppingDialog() async {
    final name = TextEditingController();
    final category = TextEditingController(text: 'Household');
    final qty = TextEditingController(text: '1');
    final estimate = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('Add shopping item'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Item')), const SizedBox(height: 8),
      TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')), const SizedBox(height: 8),
      Row(children: [Expanded(child: TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Quantity'))), const SizedBox(width: 8), Expanded(child: TextField(controller: estimate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Estimated total', prefixText: r'$ ')))]),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Add'))]));
    if (ok == true && name.text.trim().isNotEmpty) {
      await AppDb.i.insert('shopping_items', {'name': name.text.trim(), 'category': category.text.trim().isEmpty ? 'Household' : category.text.trim(), 'qty': double.tryParse(qty.text) ?? 1.0, 'estimated_cents': centsFromText(estimate.text), 'checked': 0, 'stock_item_id': null, 'created_at': AppDb.i.now()});
      widget.refresh();
    }
  }

  Future<void> _stockDialog({Map<String, Object?>? existing}) async {
    final name = TextEditingController(text: existing?['name']?.toString() ?? '');
    final category = TextEditingController(text: existing?['category']?.toString() ?? 'Household');
    final onHand = TextEditingController(text: existing == null ? '' : (existing['on_hand'] as num).toString());
    final annual = TextEditingController(text: existing == null ? '' : (existing['annual_need'] as num).toString());
    final reserve = TextEditingController(text: existing == null ? '' : (existing['reserve_qty'] as num).toString());
    final pack = TextEditingController(text: existing == null ? '1' : (existing['package_qty'] as num).toString());
    final cost = TextEditingController(text: existing == null ? '' : ((existing['package_cost_cents'] as int) / 100).toStringAsFixed(2));
    final reorder = TextEditingController(text: existing == null ? '' : (existing['reorder_point'] as num).toString());
    final store = TextEditingController(text: existing?['preferred_store']?.toString() ?? '');
    final notes = TextEditingController(text: existing?['notes']?.toString() ?? '');
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text(existing == null ? 'Add stockpile item' : 'Edit stockpile item'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Item')), const SizedBox(height: 8), TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')), const SizedBox(height: 8),
      Row(children: [Expanded(child: TextField(controller: onHand, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'On hand'))), const SizedBox(width: 8), Expanded(child: TextField(controller: annual, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Yearly need')))]), const SizedBox(height: 8),
      Row(children: [Expanded(child: TextField(controller: reserve, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Desired reserve'))), const SizedBox(width: 8), Expanded(child: TextField(controller: reorder, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Reorder point')))]), const SizedBox(height: 8),
      Row(children: [Expanded(child: TextField(controller: pack, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Units per package'))), const SizedBox(width: 8), Expanded(child: TextField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Package cost', prefixText: r'$ ')))]), const SizedBox(height: 8),
      TextField(controller: store, decoration: const InputDecoration(labelText: 'Preferred store')), const SizedBox(height: 8), TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save'))]));
    if (ok == true && name.text.trim().isNotEmpty) {
      final row = {'name': name.text.trim(), 'category': category.text.trim().isEmpty ? 'Household' : category.text.trim(), 'on_hand': double.tryParse(onHand.text) ?? 0.0, 'annual_need': double.tryParse(annual.text) ?? 0.0, 'reserve_qty': double.tryParse(reserve.text) ?? 0.0, 'package_qty': math.max(.0001, double.tryParse(pack.text) ?? 1.0), 'package_cost_cents': centsFromText(cost.text), 'reorder_point': double.tryParse(reorder.text) ?? 0.0, 'preferred_store': store.text.trim(), 'notes': notes.text.trim(), 'active': 1};
      if (existing == null) await AppDb.i.insert('stock_items', {...row, 'created_at': AppDb.i.now()}); else await AppDb.i.update('stock_items', row, existing['id'] as int);
      widget.refresh();
    }
  }

  Future<void> _addStockToShopping(Map<String, Object?> stock, {int? suggestedPackages}) async {
    final packages = suggestedPackages ?? 1;
    final existing = await AppDb.i.rows('shopping_items', where: 'stock_item_id=? AND checked=0', args: [stock['id']], limit: 1);
    if (existing.isNotEmpty) {
      final row = existing.first;
      await AppDb.i.update('shopping_items', {'qty': (row['qty'] as num).toDouble() + packages, 'estimated_cents': (row['estimated_cents'] as int) + packages * (stock['package_cost_cents'] as int)}, row['id'] as int);
    } else {
      await AppDb.i.insert('shopping_items', {'name': stock['name'], 'category': stock['category'], 'qty': packages.toDouble(), 'estimated_cents': packages * (stock['package_cost_cents'] as int), 'checked': 0, 'stock_item_id': stock['id'], 'created_at': AppDb.i.now()});
    }
    widget.refresh();
    if (mounted) showMessage(context, '${stock['name']} added to shopping.');
  }
}