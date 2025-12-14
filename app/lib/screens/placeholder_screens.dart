import 'package:flutter/material.dart';

// Placeholder screens (accidentally deleted during refactoring)
// These will be properly implemented in future phases

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text("設定")), body: const Center(child: Text("設定画面（工事中）")));
}

class LectureScreen extends StatelessWidget {
  const LectureScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text("授業動画")), body: const Center(child: Text("授業動画画面（工事中）")));
}

class RoadmapScreen extends StatelessWidget {
  const RoadmapScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text("ロードマップ")), body: const Center(child: Text("ロードマップ画面（工事中）")));
}

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text("分析")), body: const Center(child: Text("分析画面（工事中）")));
}

class ExamPlannerScreen extends StatelessWidget {
  const ExamPlannerScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text("試験対策")), body: const Center(child: Text("試験対策画面（工事中）")));
}
