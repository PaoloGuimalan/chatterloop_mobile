import 'package:flutter/material.dart';

class SpinningLoaderWidget extends StatelessWidget {
  final bool isLoading;
  final bool isFromServer;

  const SpinningLoaderWidget(
      {super.key, required this.isLoading, required this.isFromServer});

  @override
  Widget build(BuildContext context) {
    return isLoading
        ? Container(
            width: double.infinity,
            height: 50.0, // You can adjust the height as needed
            color: Colors.transparent, // Transparent background
            child: Align(
              alignment: Alignment.topCenter,
              child: Transform.scale(
                scale: 0.7,
                child: CircularProgressIndicator(
                  color: isFromServer
                      ? Color(0xffe69500)
                      : Color(0xFF1c7def), // Customize the color as needed
                ),
              ),
            ),
          )
        : SizedBox.shrink(); // If not loading, return an empty space
  }
}
