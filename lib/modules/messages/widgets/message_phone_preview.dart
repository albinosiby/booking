import 'package:flutter/material.dart';
import 'message_chat_preview.dart';

/// Desktop presentation: the message as an outgoing WhatsApp chat bubble on a
/// phone. Decorative only; the underlying message is never changed.
class MessagePhonePreview extends StatelessWidget {
  const MessagePhonePreview({
    super.key,
    required this.message,
    this.sample = false,
    this.height = 600,
  });
  final String message;
  final bool sample;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final header = dark ? const Color(0xFF1F2C34) : const Color(0xFF008069);
    final wallpaper = dark ? const Color(0xFF0B141A) : const Color(0xFFEFEAE2);
    final bubble = dark ? const Color(0xFF005C4B) : const Color(0xFFD9FDD3);
    final ink = dark ? const Color(0xFFE9EDEF) : const Color(0xFF111B21);
    final bar = dark ? const Color(0xFF1F2C34) : Colors.white;
    return Center(
      child: Container(
        width: 330,
        height: height,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2A2F33) : const Color(0xFF1C1F22),
          borderRadius: BorderRadius.circular(42),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .5 : .16),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: ColoredBox(
            color: wallpaper,
            child: Column(
              children: [
                Container(
                  color: header,
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 12),
                  child: Column(
                    children: [
                      Container(
                        width: 84,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.arrow_back_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.white.withValues(
                              alpha: .22,
                            ),
                            child: const Icon(
                              Icons.person_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Customer',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  sample ? 'Sample booking' : 'WhatsApp',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: .75),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.more_vert_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: bar,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              sample ? 'Preview with sample values' : 'Preview',
                              style: TextStyle(
                                fontSize: 11,
                                color: ink.withValues(alpha: .65),
                              ),
                            ),
                          ),
                        ),
                        Container(
                          constraints: const BoxConstraints(maxWidth: 270),
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                          decoration: BoxDecoration(
                            color: bubble,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(10),
                              topRight: Radius.circular(2),
                              bottomLeft: Radius.circular(10),
                              bottomRight: Radius.circular(10),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .08),
                                blurRadius: 1,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              SelectableText.rich(
                                messagePreviewSpan(
                                  message.isEmpty
                                      ? 'Your message preview appears here.'
                                      : message,
                                ),
                                style: t.textTheme.bodyMedium?.copyWith(
                                  color: ink,
                                  fontSize: 13.5,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Icon(
                                Icons.done_all_rounded,
                                size: 15,
                                color: Color(0xFF53BDEB),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            color: bar,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Message',
                            style: TextStyle(
                              fontSize: 14,
                              color: ink.withValues(alpha: .5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const CircleAvatar(
                        radius: 19,
                        backgroundColor: Color(0xFF00A884),
                        child: Icon(
                          Icons.mic_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
