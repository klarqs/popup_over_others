import 'package:buildcrypto/splash_screen_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SplashScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetBuilder<SplashScreenController>(
      init: SplashScreenController(),
      builder: (controller) => Scaffold(
        backgroundColor: Colors.black.withOpacity(.8),
        body: Stack(
          children: [
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/icon/icon_.png',
                    height: 45,
                  ),
                  SizedBox(width: 0,),
                  Text(
                    'tracecoin',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 35,
                        fontWeight: FontWeight.bold
                    ),
                  ),
                  SizedBox(
                    width: 8,
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '©',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        letterSpacing: .3),
                  ),
                  Text(
                    ' Fluttering Around',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: .3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
