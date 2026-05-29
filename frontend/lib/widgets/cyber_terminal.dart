import 'package:flutter/material.dart';

class CyberTerminal extends StatefulWidget {
  final List<String> logs;
  final String streamedMessage;
  final bool isIntercepted;

  const CyberTerminal({
    super.key,
    required this.logs,
    required this.streamedMessage,
    required this.isIntercepted,
  });

  @override
  State<CyberTerminal> createState() => _CyberTerminalState();
}

class _CyberTerminalState extends State<CyberTerminal> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CyberTerminal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color terminalRed = const Color(0xFFFF1744);
    final Color terminalGreen = const Color(0xFF00E676);
    final Color terminalBlue = const Color(0xFF2962FF);

    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isIntercepted 
              ? terminalRed.withOpacity(0.3) 
              : Colors.white10,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.isIntercepted 
                ? terminalRed.withOpacity(0.08) 
                : Colors.black.withOpacity(0.6),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: const CustomPaint(
                painter: _ScanlinePainter(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: widget.logs.length + (widget.isIntercepted ? 1 : 0),
                itemBuilder: (context, index) {
                  if (widget.isIntercepted && index == widget.logs.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(
                        widget.streamedMessage,
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Courier',
                          fontSize: 13,
                          height: 1.5,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: Colors.white.withOpacity(0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final String log = widget.logs[index];
                  Color logColor = Colors.white70;
                  bool isAlert = log.contains("[ALERT]");
                  bool isSystem = log.contains("[SYSTEM]") || log.contains("[MEMORY]") || log.contains("[LOCKDOWN]") || log.contains("[FIREWALL]");
                  bool isBroker = log.contains("[BROKER]");
                  
                  if (isAlert) {
                    logColor = terminalRed;
                  } else if (isSystem) {
                    logColor = terminalGreen.withOpacity(0.85);
                  } else if (isBroker) {
                    logColor = terminalBlue;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5.0),
                    child: Text(
                      log,
                      style: TextStyle(
                        color: logColor,
                        fontFamily: 'Courier',
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: isAlert ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: widget.isIntercepted ? terminalRed : terminalGreen,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: widget.isIntercepted ? terminalRed : terminalGreen,
                          blurRadius: 6,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isIntercepted ? "LOCKED" : "MONITOR",
                    style: TextStyle(
                      color: widget.isIntercepted ? terminalRed : terminalGreen,
                      fontFamily: 'Courier',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.015)
      ..strokeWidth = 1.0;
    
    for (double y = 0; y < size.height; y += 4.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
