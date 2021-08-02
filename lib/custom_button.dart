import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CustomButton extends StatelessWidget {
  final Function onTap;
  final String text;
  final Color buttonColor;
  final Color textColor;
  final Icon icon;

  const CustomButton({
    Key key,
    this.onTap,
    this.text = "Text",
    this.buttonColor = Colors.blueAccent,
    this.textColor = Colors.white,
    this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: Get.width,
      height: 52,
      child: RaisedButton(
        color: buttonColor,

        shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.white, width: .5),
            borderRadius: BorderRadius.circular(50)),
        onPressed: onTap,
        elevation: 0,
        focusElevation: 0,
        splashColor: Color(0XFFF4F4F4).withOpacity(.1),
        highlightElevation: 0,
        highlightColor: Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            SizedBox(
              width: 4,
            ),
            Text(
              text,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
