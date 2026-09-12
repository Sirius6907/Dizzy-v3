import 'package:flutter/material.dart';

import '../../services/profiles/dizzy_profile_service.dart';
import '../../services/profiles/kids_mode.dart';
import '../../services/theme/app_theme_service.dart';

/// S3B (v1.1.9): local-first profile selector and manager.
class ProfilesSettingsPage extends StatelessWidget {
  const ProfilesSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1017),
        surfaceTintColor: Colors.transparent,
        title: const Text('Profiles',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreate(context),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add profile'),
      ),
      body: ValueListenableBuilder(
        valueListenable: DizzyProfileService.profiles,
        builder: (context, profiles, _) => ValueListenableBuilder<String?>(
          valueListenable: DizzyProfileService.activeProfileId,
          builder: (context, activeId, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Choose who is watching',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                DizzyProfileService.isCloudUser
                    ? 'Profiles sync privately across your devices.'
                    : 'Local profiles work offline. Cloud sync turns on automatically.',
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 18),
              for (final p in profiles)
                _profileTile(context, p, activeId == p.id, palette),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileTile(BuildContext context, dynamic p, bool active, dynamic palette) {
    return Card(
      color: active
          ? palette.primaryColor.withValues(alpha: 0.16)
          : const Color(0xFF11141B),
      child: ListTile(
        // Polish P15: kids avatar wears a gold ring + cub badge.
        leading: Semantics(
          label: p.isKids ? 'Kids profile ${p.name}' : 'Profile ${p.name}',
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: KidsMode.ring(isKids: p.isKids),
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  backgroundColor:
                      palette.primaryColor.withValues(alpha: 0.22),
                  child:
                      Text(p.avatar, style: const TextStyle(fontSize: 22)),
                ),
              ),
              if (p.isKids)
                const Positioned(
                  right: -4,
                  bottom: -2,
                  child: Text(KidsMode.kKidsBadge,
                      style: TextStyle(fontSize: 16)),
                ),
            ],
          ),
        ),
        title: Text(p.name,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        subtitle: Text(
          KidsMode.subtitle(isKids: p.isKids, hasPin: p.hasPin),
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: active
            ? Icon(Icons.check_circle_rounded, color: palette.primaryColor)
            : const Icon(Icons.chevron_right_rounded, color: Colors.white54),
        onTap: () async {
          if (p.hasPin) {
            final pin = await _askPin(context, 'Enter PIN for ${p.name}');
            if (pin == null) return;
            await DizzyProfileService.select(p.id, pin: pin);
          } else {
            await DizzyProfileService.select(p.id);
          }
        },
        onLongPress: () async {
          if (DizzyProfileService.profiles.value.length <= 1) return;
          final delete = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text('Delete ${p.name}?'),
              content: const Text('This only deletes the profile. Local media stays on this device.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
              ],
            ),
          );
          if (delete == true) await DizzyProfileService.delete(p.id);
        },
      ),
    );
  }

  Future<void> _showCreate(BuildContext context) async {
    final name = TextEditingController();
    final pin = TextEditingController();
    var kids = false;
    var avatar = '✨';
    final created = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('New profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              TextField(
                controller: pin,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'Optional 4–6 digit PIN'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Kids profile'),
                subtitle: const Text('Marked kid-safe; stricter filtering comes in the next pass.'),
                value: kids,
                onChanged: (v) => setState(() => kids = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                await DizzyProfileService.create(
                  name: name.text,
                  avatar: avatar,
                  isKids: kids,
                  pin: pin.text.isEmpty ? null : pin.text,
                );
                if (c.mounted) Navigator.pop(c, true);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile created')));
    }
  }

  Future<String?> _askPin(BuildContext context, String title) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'PIN'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Unlock')),
        ],
      ),
    );
  }
}
