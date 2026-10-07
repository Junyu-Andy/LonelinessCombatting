import 'package:flutter_test/flutter_test.dart';
import 'package:app_demo/features/researcher_dashboard/data/dashboard_access.dart';

/// T12 (decision 0021): blinded staff never see per-arm counts or
/// single-arm sections; participants are denied.  T19 (decision 0029)
/// renamed the roles: the PI is blinded; the old names grant nothing.
void main() {
  test('role claim maps to access level', () {
    expect(
      DashboardAccess.fromClaims({'role': 'unblinded'}),
      DashboardAccess.unblinded,
    );
    expect(
      DashboardAccess.fromClaims({'role': 'blinded'}),
      DashboardAccess.blinded,
    );
    // Pre-T19 claims: 'pi' used to be UNBLINDED — it must not be now.
    expect(DashboardAccess.fromClaims({'role': 'pi'}), DashboardAccess.denied);
    expect(DashboardAccess.fromClaims({'role': 'researcher'}),
        DashboardAccess.denied);
    expect(
      DashboardAccess.fromClaims({'role': 'admin'}),
      DashboardAccess.denied,
    );
    expect(DashboardAccess.fromClaims({}), DashboardAccess.denied);
    expect(DashboardAccess.fromClaims(null), DashboardAccess.denied);
  });

  test('blinded role sees no arm-revealing sections', () {
    const b = DashboardAccess.blinded;
    expect(b.allowed, isTrue);
    expect(b.showsArmCounts, isFalse);
    expect(b.showsSingleArmSections, isFalse);
    const u = DashboardAccess.unblinded;
    expect(u.showsArmCounts, isTrue);
    expect(u.showsSingleArmSections, isTrue);
    expect(DashboardAccess.denied.allowed, isFalse);
  });
}
