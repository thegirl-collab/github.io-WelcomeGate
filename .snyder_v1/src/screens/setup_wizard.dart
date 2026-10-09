import 'package:flutter/material.dart';
import '../db.dart';
import '../services/property_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';

class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});
  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  int step = 0;
  final displayName = TextEditingController(text: 'Cyn');
  final householdName = TextEditingController(text: 'Snyder Family');
  final takeHome = TextEditingController();
  final availableCash = TextEditingController();
  final householdBuffer = TextEditingController();
  DateTime payday = DateTime.now().add(const Duration(days: 14));
  final propertyGoal = TextEditingController();
  final emergencyGoal = TextEditingController();
  bool propertyEnabled = true;
  bool seedLists = true;
  final propertyLabel = TextEditingController(text: 'Rental Property');
  final propertyAddress = TextEditingController();
  final landlordName = TextEditingController();
  final landlordPhone = TextEditingController();
  final landlordEmail = TextEditingController();
  final tenantName = TextEditingController();
  final tenantPhone = TextEditingController();
  final tenantEmail = TextEditingController();
  final rentAmount = TextEditingController();
  final dueDay = TextEditingController(text: '1');
  DateTime trackingStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool saving = false;

  @override
  void dispose() {
    for (final c in [displayName, householdName, takeHome, availableCash, householdBuffer, propertyGoal, emergencyGoal, propertyLabel, propertyAddress, landlordName, landlordPhone, landlordEmail, tenantName, tenantPhone, tenantEmail, rentAmount, dueDay]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> finish() async {
    setState(() => saving = true);
    try {
      final db = AppDb.i;
      await db.setSetting('display_name', displayName.text.trim().isEmpty ? 'Cyn' : displayName.text.trim());
      await db.setSetting('household_name', householdName.text.trim().isEmpty ? 'Snyder Family' : householdName.text.trim());
      await db.setSetting('expected_takehome_cents', centsFromText(takeHome.text));
      await db.setSetting('available_cash_cents', centsFromText(availableCash.text));
      await db.setSetting('household_buffer_cents', centsFromText(householdBuffer.text));
      await db.setSetting('next_payday', isoDate(payday));
      await db.setSetting('pay_frequency_days', 14);
      if (centsFromText(propertyGoal.text) > 0) {
        await db.insert('goals', {
          'name': 'Property Purchase', 'target_cents': centsFromText(propertyGoal.text), 'saved_cents': 0, 'target_date': null,
          'per_paycheck_cents': 0, 'priority': 3, 'category': 'Property', 'active': 1, 'created_at': db.now(),
        });
      }
      if (centsFromText(emergencyGoal.text) > 0) {
        await db.insert('goals', {
          'name': 'Emergency Fund', 'target_cents': centsFromText(emergencyGoal.text), 'saved_cents': 0, 'target_date': null,
          'per_paycheck_cents': 0, 'priority': 2, 'category': 'Emergency', 'active': 1, 'created_at': db.now(),
        });
      }
      if (seedLists) await _seedSnyderLists();
      if (propertyEnabled) {
        final pid = await PropertyService.createProperty(
          label: propertyLabel.text.trim().isEmpty ? 'Rental Property' : propertyLabel.text.trim(),
          address: propertyAddress.text.trim(), landlordName: landlordName.text.trim(), landlordPhone: landlordPhone.text.trim(), landlordEmail: landlordEmail.text.trim(),
          tenantName: tenantName.text.trim(), tenantPhone: tenantPhone.text.trim(), tenantEmail: tenantEmail.text.trim(), trackingStart: trackingStart,
        );
        if (centsFromText(rentAmount.text) > 0) {
          await PropertyService.addRentRule(pid, trackingStart, centsFromText(rentAmount.text), int.tryParse(dueDay.text) ?? 1);
          await PropertyService.postChargesThroughToday(pid);
        }
      }
      await db.setSetting('setup_complete', 1);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AppShell()), (_) => false);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _seedSnyderLists() async {
    final db = AppDb.i;
    for (final name in ['Toilet Paper', 'Paper Towels', 'Dog Food', 'Laundry Detergent', 'Shampoo', 'Coffee', 'Trash Bags', 'Crow Peanuts']) {
      await db.insert('stock_items', {
        'name': name, 'category': name.contains('Dog') ? 'Pets' : name.contains('Crow') ? 'Crow Station' : 'Household',
        'on_hand': 0.0, 'annual_need': 0.0, 'reserve_qty': 0.0, 'package_qty': 1.0, 'package_cost_cents': 0,
        'reorder_point': 0.0, 'preferred_store': '', 'notes': '', 'active': 1, 'created_at': db.now(),
      });
    }
    for (final t in [
      ['Dishes', 'Daily'], ['Laundry', 'Weekly'], ['Take Out Trash', 'Weekly'], ['Mow Lawn', 'As needed'], ['Homeschool Prep', 'Weekly'], ['Clean Bathrooms', 'Weekly']
    ]) {
      await db.insert('tasks', {
        'name': t[0], 'category': t[0] == 'Homeschool Prep' ? 'Homeschool' : 'Household', 'due_date': null, 'due_label': t[1],
        'recurrence': t[1].toLowerCase(), 'done': 0, 'completed_at': null, 'created_at': db.now(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_welcome(), _money(), _goals(), _property()];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.asset('assets/snyder_logo.png', width: 76, height: 76)),
                const SizedBox(width: 14),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SNYDER FAMILY', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.3)),
                  Text('Private household command center', style: TextStyle(color: SnyderColors.lavender)),
                ])),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: LinearProgressIndicator(value: (step + 1) / pages.length, minHeight: 7, borderRadius: BorderRadius.circular(99), color: SnyderColors.cyan, backgroundColor: SnyderColors.line),
            ),
            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(18), child: pages[step])),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: Row(children: [
                if (step > 0) Expanded(child: OutlinedButton(onPressed: saving ? null : () => setState(() => step--), child: const Text('Back'))),
                if (step > 0) const SizedBox(width: 10),
                Expanded(child: FilledButton(
                  onPressed: saving ? null : () => step < pages.length - 1 ? setState(() => step++) : finish(),
                  child: Text(saving ? 'Building Snyder Family…' : step < pages.length - 1 ? 'Continue' : 'Finish Setup'),
                )),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _welcome() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Welcome home. 🖤', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
    const SizedBox(height: 10),
    const Text('This app is built to be your one-stop Snyder household system: bills, paycheck planning, savings, yearly stockpile, tasks, family/home goals, and Property Hub.'),
    const SizedBox(height: 18),
    SnyderCard(accent: SnyderColors.green, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sectionTitle(Icons.phonelink_lock, 'Phone-only by design', color: SnyderColors.green),
      const SizedBox(height: 9),
      const Text('No account. No cloud database. No bank connection. The finished APK does not request Internet access. Android cloud backup is disabled.'),
      const SizedBox(height: 8),
      const Text('You can still create a password-encrypted manual backup whenever YOU choose.', style: TextStyle(color: SnyderColors.muted)),
    ])),
    const SizedBox(height: 18),
    TextField(controller: displayName, decoration: const InputDecoration(labelText: 'Your dashboard name')),
    const SizedBox(height: 10),
    TextField(controller: householdName, decoration: const InputDecoration(labelText: 'Household name')),
    const SizedBox(height: 14),
    SwitchListTile(contentPadding: EdgeInsets.zero, value: seedLists, onChanged: (v) => setState(() => seedLists = v), title: const Text('Start with Snyder household lists'), subtitle: const Text('Adds common stockpile items, pups/crow supplies, chores, and homeschool prep — no fake dollar amounts.')),
  ]);

  Widget _money() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Money foundation', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
    const SizedBox(height: 8), const Text('These are planning values. You can change them any time.'), const SizedBox(height: 16),
    TextField(controller: takeHome, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Expected take-home per biweekly paycheck', prefixText: r'$ ')),
    const SizedBox(height: 10),
    ListTile(contentPadding: EdgeInsets.zero, title: const Text('Next payday'), subtitle: Text(shortDate(payday)), trailing: const Icon(Icons.calendar_month, color: SnyderColors.cyan), onTap: () async { final d = await pickDate(context, payday); if (d != null) setState(() => payday = d); }),
    const SizedBox(height: 10),
    TextField(controller: availableCash, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Available cash / checking balance for forecasts', prefixText: r'$ ')),
    const SizedBox(height: 10),
    TextField(controller: householdBuffer, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Household essentials / flexible budget per paycheck', prefixText: r'$ ')),
    const SizedBox(height: 12),
    const Text('Bill Smart Split will use actual due dates and the real number of biweekly checks left before each bill is due.', style: TextStyle(color: SnyderColors.muted)),
  ]);

  Widget _goals() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Big Snyder goals', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
    const SizedBox(height: 8), const Text('Optional starting goals. You can add unlimited goals later.'), const SizedBox(height: 16),
    TextField(controller: propertyGoal, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Property purchase target', prefixText: r'$ ')),
    const SizedBox(height: 10),
    TextField(controller: emergencyGoal, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Emergency fund target', prefixText: r'$ ')),
    const SizedBox(height: 16),
    SnyderCard(accent: SnyderColors.violet, child: const Text('Savings goals can use either a fixed amount per paycheck or a target date. If you give a deadline, Snyder Family calculates what each remaining paycheck needs to contribute.')),
  ]);

  Widget _property() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [const Expanded(child: Text('Property Hub', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900))), Switch(value: propertyEnabled, onChanged: (v) => setState(() => propertyEnabled = v))]),
    const Text('Merge your landlord records into the same private app. You can also import your existing Landlord Control Center v7 JSON later.'),
    if (propertyEnabled) ...[
      const SizedBox(height: 16),
      TextField(controller: propertyLabel, decoration: const InputDecoration(labelText: 'Property label')),
      const SizedBox(height: 8), TextField(controller: propertyAddress, decoration: const InputDecoration(labelText: 'Rental property address')),
      const SizedBox(height: 8), TextField(controller: landlordName, decoration: const InputDecoration(labelText: 'Landlord / manager name')),
      const SizedBox(height: 8), Row(children: [Expanded(child: TextField(controller: landlordPhone, decoration: const InputDecoration(labelText: 'Landlord phone'))), const SizedBox(width: 8), Expanded(child: TextField(controller: landlordEmail, decoration: const InputDecoration(labelText: 'Landlord email')))]),
      const SizedBox(height: 8), TextField(controller: tenantName, decoration: const InputDecoration(labelText: 'Tenant name')),
      const SizedBox(height: 8), Row(children: [Expanded(child: TextField(controller: tenantPhone, decoration: const InputDecoration(labelText: 'Tenant phone'))), const SizedBox(width: 8), Expanded(child: TextField(controller: tenantEmail, decoration: const InputDecoration(labelText: 'Tenant email')))]),
      const SizedBox(height: 8), Row(children: [Expanded(child: TextField(controller: rentAmount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Current monthly rent', prefixText: r'$ '))), const SizedBox(width: 8), SizedBox(width: 105, child: TextField(controller: dueDay, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Due day')))]),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Ledger tracking begins'), subtitle: Text(shortDate(trackingStart)), trailing: const Icon(Icons.calendar_today, color: SnyderColors.violet), onTap: () async { final d = await pickDate(context, trackingStart); if (d != null) setState(() => trackingStart = d); }),
    ],
  ]);
}