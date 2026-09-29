import 'package:flutter/material.dart';

import '../../design/dizzy_tactile.dart';
import '../../design/dizzy_tokens.dart';
import '../../services/my_list/custom_list_policy.dart';
import '../../services/my_list/custom_list_service.dart';
import '../../services/my_list/pin_lock_policy.dart';
import '../../services/profiles/dizzy_profile_service.dart';
import '../../widgets/tactile/dizzy_tactile_button.dart';
import '../../widgets/tactile/dizzy_tactile_card.dart';
import '../../widgets/common/offline_aware_scaffold.dart';

/// F3 — hand-made lists for the person using the app right now.
///
/// Everything on this screen is Easy English and one tap deep: a list is
/// made with a name, titles are added from any title page, and the whole
/// folder can be locked with four digits so a borrowed phone stays a
/// borrowed phone.
class CustomListsPage extends StatefulWidget {
  final String? profileId;

  const CustomListsPage({super.key, this.profileId});

  @override
  State<CustomListsPage> createState() => _CustomListsPageState();
}

class _CustomListsPageState extends State<CustomListsPage> {
  final TextEditingController _nameController = TextEditingController();
  String? _editingId;
  bool _locked = false;

  String get _profileId =>
      widget.profileId ?? DizzyProfileService.activeProfileId.value ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    if (_profileId.isEmpty) return;
    await CustomListService.load(_profileId);
    final hash = await CustomListService.storedPinHash(_profileId);
    if (!mounted) return;
    setState(() {
      // A lock is only something to open if one was actually set.
      _locked = hash != null && hash.isNotEmpty;
    });
  }

  Future<void> _submit() async {
    final name = _nameController.text;
    final ok = _editingId == null
        ? await CustomListService.create(name)
        : await CustomListService.rename(_editingId!, name);
    if (!mounted) return;
    if (!ok) {
      _say(_editingId == null
          ? 'Pick a different name. Lists keep names short.'
          : 'That name is already used by another list.');
      return;
    }
    setState(() {
      _editingId = null;
      _nameController.clear();
    });
    _say('List saved.');
  }

  void _startRename(CustomList list) {
    setState(() {
      _editingId = list.id;
      _nameController.text = list.name;
    });
  }

  Future<void> _confirmDelete(CustomList list) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DizzyVoid.voidA,
        title: Text('Delete "${list.name}"?', style: const TextStyle(color: DizzyVoid.bone)),
        content: const Text(
          'This list goes away. Your titles stay saved.',
          style: TextStyle(color: DizzyVoid.ash),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it', style: TextStyle(color: DizzyVoid.ash)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: DizzyGlow.red)),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await CustomListService.delete(list.id);
    if (mounted) _say('List deleted.');
  }

  Future<void> _promptPin({required bool forSetup}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DizzyVoid.voidA,
        title: Text(
          forSetup ? 'Lock your lists' : 'Type your 4 numbers',
          style: const TextStyle(color: DizzyVoid.bone),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: PinLockPolicy.length,
          obscureText: true,
          style: const TextStyle(color: DizzyVoid.bone, fontSize: 24, letterSpacing: 10),
          decoration: const InputDecoration(
            counterText: '',
            hintText: '••••',
            hintStyle: TextStyle(color: DizzyVoid.ash),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not now', style: TextStyle(color: DizzyVoid.ash)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('OK', style: TextStyle(color: DizzyGlow.volt)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;

    if (forSetup) {
      if (!PinLockPolicy.isValid(result.trim())) {
        _say('Use 4 numbers, like 1234.');
        return;
      }
      await CustomListService.setPin(_profileId, result.trim());
      if (!mounted) return;
      setState(() => _locked = true);
      _say('Locked.');
      return;
    }

    final check = await CustomListService.unlock(_profileId, result.trim());
    if (!mounted) return;
    if (check.ok) {
      setState(() => _locked = false);
      _say('Unlocked.');
      return;
    }
    if (check.isLockedOut) {
      _say('Too many tries. Wait a little, then try again.');
      return;
    }
    _say('That is not the right code.');
  }

  void _say(String line) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(line, style: const TextStyle(color: DizzyVoid.bone)),
        backgroundColor: DizzyVoid.voidB,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return OfflineAwareScaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('My Lists', style: TextStyle(color: DizzyVoid.bone)),
        actions: [
          if (!_locked)
            IconButton(
              tooltip: 'Lock',
              onPressed: () => _promptPin(forSetup: true),
              icon: const Icon(Icons.lock_outline, color: DizzyVoid.ash),
            ),
        ],
      ),
      body: _locked ? _buildLocked() : _buildEditor(),
    );
  }

  Widget _buildLocked() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DizzySpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 48, color: DizzyGlow.volt),
            const SizedBox(height: DizzySpace.md),
            const Text(
              'Your lists are locked.',
              style: TextStyle(color: DizzyVoid.bone, fontSize: 18),
            ),
            const SizedBox(height: DizzySpace.sm),
            const Text(
              'Type your 4 numbers to open them.',
              style: TextStyle(color: DizzyVoid.ash),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DizzySpace.lg),
            DizzyTactileButton(
              height: 48,
              gradient: DizzyGradients.emberButton,
              glowColor: DizzyGlow.volt,
              onTap: () => _promptPin(forSetup: false),
              child: const Text('Open', style: TextStyle(color: DizzyVoid.bone, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return ValueListenableBuilder<List<CustomList>>(
      valueListenable: CustomListService.lists,
      builder: (context, lists, _) {
        return ListView(
          padding: const EdgeInsets.all(DizzySpace.md),
          children: [
            _buildNameField(),
            const SizedBox(height: DizzySpace.md),
            if (lists.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: DizzySpace.xl),
                child: Text(
                  'No lists yet. Name one above to start.',
                  style: TextStyle(color: DizzyVoid.ash),
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final list in lists)
                Padding(
                  padding: const EdgeInsets.only(bottom: DizzySpace.sm),
                  child: _buildRow(list),
                ),
          ],
        );
      },
    );
  }

  Widget _buildNameField() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _nameController,
            maxLength: CustomListPolicy.maxNameLength,
            style: const TextStyle(color: DizzyVoid.bone),
            decoration: InputDecoration(
              counterText: '',
              hintText: _editingId == null ? 'Name your list' : 'New name',
              hintStyle: const TextStyle(color: DizzyVoid.ash),
              filled: true,
              fillColor: DizzyVoid.voidA,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: DizzyEdge.hairline,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: DizzyEdge.hairline,
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: DizzySpace.sm),
        DizzyTactileButton(
          width: 52,
          height: 52,
          gradient: DizzyGradients.emberButton,
          glowColor: DizzyGlow.volt,
          onTap: _submit,
          child: const Icon(Icons.check, color: DizzyVoid.bone),
        ),
      ],
    );
  }

  Widget _buildRow(CustomList list) {
    return DizzyTactileCard(
      onTap: () => _startRename(list),
      padding: const EdgeInsets.all(DizzySpace.md),
      glowColor: DizzyGlow.volt,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  list.name,
                  style: const TextStyle(
                    color: DizzyVoid.bone,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  list.length == 1 ? '1 title' : '${list.length} titles',
                  style: const TextStyle(color: DizzyVoid.ash, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(list),
            icon: const Icon(Icons.delete_outline, color: DizzyVoid.ash),
          ),
        ],
      ),
    );
  }
}
