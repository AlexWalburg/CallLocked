import 'package:CallLock/browseGroups.dart';
import 'package:CallLock/main.dart';
import 'package:CallLock/manageGroups.dart';
import 'package:flutter/material.dart';
import 'package:CallLock/settings.dart';

Route navigate(int index){
  Function pushTo = [
        (BuildContext,Animation,secondAnimation) => MyApp(),
        (BuildContext,Animation,secondAnimation) => ManageGroupsPage(),
        (BuildContext,Animation,secondAnimation) => BrowseGroupsPage(),
        (BuildContext,Animation,secondAnimation) => SettingsPage()
  ][index];
  return PageRouteBuilder(pageBuilder: pushTo, transitionsBuilder: (context, animation, secondaryAnimation, child){return child;});
}