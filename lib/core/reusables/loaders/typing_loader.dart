import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/design/tokens.dart';

class TypingIndicator extends StatefulWidget {
  final bool isTyping;
  final CLPalette p;
  const TypingIndicator({super.key, required this.isTyping, required this.p});
  @override
  TypingIndicatorState createState() => TypingIndicatorState();
}

class TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation1;
  late Animation<double> _animation2;
  late Animation<double> _animation3;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _animation1 = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6)),
    );
    _animation2 = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.2, 0.8)),
    );
    _animation3 = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.4, 1.0)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 0, bottom: 0, left: 5, right: 0),
      child: Column(
        children: [
          SizedBox(
            height: widget.isTyping ? 7 : 0,
          ),
          Row(
            children: [
              AnimatedContainer(
                width: widget.isTyping ? 60 : 0,
                height: widget.isTyping ? 40 : 0,
                decoration: BoxDecoration(
                    color: widget.p.surface3,
                    borderRadius: BorderRadius.circular(10)),
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: Padding(
                  padding: EdgeInsets.all(5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedDot(animation: _animation1, p: widget.p),
                      const SizedBox(width: 5),
                      AnimatedDot(animation: _animation2, p: widget.p),
                      const SizedBox(width: 5),
                      AnimatedDot(animation: _animation3, p: widget.p),
                    ],
                  ),
                ),
              ),
              Expanded(
                  child: SizedBox(
                height: 0,
              ))
            ],
          )
        ],
      ),
    );
  }
}

class AnimatedDot extends AnimatedWidget {
  final CLPalette p;
  const AnimatedDot(
      {super.key, required Animation<double> animation, required this.p})
      : super(listenable: animation);

  Animation<double> get animation => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: animation.value,
      child: Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          color: p.text,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
