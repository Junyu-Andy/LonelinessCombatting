/// Orange strip on the home page while the tester schedule simulator is
/// active, so nobody forgets the app is running on a fake date.
library;

import 'package:flutter/material.dart';

import '../../../../core/scheduling/schedule_simulator.dart';
import '../../../../core/time/app_clock.dart';

class SimulatedClockStrip extends StatelessWidget {
  const SimulatedClockStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppClock.instance,
      builder: (context, _) {
        if (!AppClock.instance.isSimulated) return const SizedBox.shrink();
        final t = AppClock.now();
        String two(int v) => v.toString().padLeft(2, '0');
        return Material(
          color: const Color(0xFFE65100),
          child: InkWell(
            onTap: AppClock.instance.clear,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.schedule, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '測試：模擬時間 ${t.year}-${two(t.month)}-${two(t.day)} '
                      '${ScheduleSimulator.weekdayZh(t)} ${two(t.hour)}:${two(t.minute)}'
                      '　（撳呢度返回真實時間）',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
