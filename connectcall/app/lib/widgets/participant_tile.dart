import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

/// One participant: their camera if it is on, otherwise an avatar with
/// initials. Rebuilds itself whenever the participant's state changes.
class ParticipantTile extends StatelessWidget {
  const ParticipantTile({super.key, required this.participant, this.compact = false});

  final Participant participant;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: participant,
      builder: (context, _) {
        final video = _activeVideoTrack(participant);
        final isLocal = participant is LocalParticipant;
        final name = participant.name.isNotEmpty ? participant.name : participant.identity;
        final label = isLocal ? '$name (you)' : name;
        final micOn = participant.isMicrophoneEnabled();

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1E26),
            borderRadius: BorderRadius.circular(compact ? 10 : 14),
            border: Border.all(
              color: participant.isSpeaking ? Colors.lightGreenAccent : Colors.transparent,
              width: 2.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (video != null)
                VideoTrackRenderer(video, fit: VideoViewFit.cover)
              else
                _Avatar(name: name, compact: compact),
              Positioned(
                left: 8,
                bottom: 8,
                right: 8,
                child: Row(children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (!micOn) ...[
                          const Icon(Icons.mic_off, size: 14, color: Colors.redAccent),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white, fontSize: compact ? 11 : 13),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The participant's camera track, if it is published, subscribed and unmuted.
  static VideoTrack? _activeVideoTrack(Participant p) {
    for (final pub in p.videoTrackPublications) {
      if (pub.isScreenShare || pub.muted) continue;
      final track = pub.track;
      if (track is VideoTrack) return track;
    }
    return null;
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.compact});

  final String name;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
            ? parts.first.characters.first.toUpperCase()
            : '${parts.first.characters.first}${parts.last.characters.first}'.toUpperCase();
    return Center(
      child: CircleAvatar(
        radius: compact ? 22 : 40,
        backgroundColor: Colors.indigo.shade400,
        child: Text(initials, style: TextStyle(fontSize: compact ? 16 : 28, color: Colors.white)),
      ),
    );
  }
}
