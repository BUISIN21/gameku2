import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

/// Lets the user pick microphone, camera and speaker. Mainly for laptops,
/// which often have several devices (built-in, USB headset, webcam...).
class DeviceSettingsSheet extends StatefulWidget {
  const DeviceSettingsSheet({super.key, required this.room});

  final Room room;

  static Future<void> show(BuildContext context, Room room) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => DeviceSettingsSheet(room: room),
      );

  @override
  State<DeviceSettingsSheet> createState() => _DeviceSettingsSheetState();
}

class _DeviceSettingsSheetState extends State<DeviceSettingsSheet> {
  List<MediaDevice> _devices = const [];
  StreamSubscription<List<MediaDevice>>? _sub;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _sub = Hardware.instance.onDeviceChange.stream.listen((d) => setState(() => _devices = d));
    _load();
  }

  Future<void> _load() async {
    try {
      final devices = await Hardware.instance.enumerateDevices();
      if (mounted) setState(() => _devices = devices);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not list devices: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _select(MediaDevice device) async {
    try {
      switch (device.kind) {
        case 'audioinput':
          await widget.room.setAudioInputDevice(device);
        case 'videoinput':
          await widget.room.setVideoInputDevice(device);
        case 'audiooutput':
          await widget.room.setAudioOutputDevice(device);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not switch device: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hw = Hardware.instance;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: _loading
            ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            : ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  _section('Microphone', Icons.mic, 'audioinput', hw.selectedAudioInput),
                  _section('Camera', Icons.videocam, 'videoinput', hw.selectedVideoInput),
                  _section('Speaker', Icons.volume_up, 'audiooutput', hw.selectedAudioOutput),
                ],
              ),
      ),
    );
  }

  Widget _section(String title, IconData icon, String kind, MediaDevice? selected) {
    final devices = _devices.where((d) => d.kind == kind && d.deviceId.isNotEmpty).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Row(children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
        ]),
      ),
      if (devices.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('No selectable devices found (the browser may choose automatically).'),
        )
      else
        RadioGroup<String>(
          groupValue: selected?.deviceId,
          onChanged: (id) {
            final d = devices.where((d) => d.deviceId == id).firstOrNull;
            if (d != null) _select(d);
          },
          child: Column(children: [
            for (final d in devices)
              RadioListTile<String>(
                dense: true,
                value: d.deviceId,
                title: Text(d.label.isNotEmpty ? d.label : 'Device ${devices.indexOf(d) + 1}'),
              ),
          ]),
        ),
    ]);
  }
}
