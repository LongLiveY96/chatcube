import localUnitTest from './LocalUnit.test';
import refactorGuardTest from './RefactorGuard.test';

export default function testsuite() {
  localUnitTest();
  refactorGuardTest();
}
