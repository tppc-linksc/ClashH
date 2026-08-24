import { describe, it, expect } from '@ohos/hypium';
import { isHttpSubscription, normalizeProfileInput } from '../../../main/ets/service/ProfileInput';

export default function profileInputAbilityTest() {
  describe('ProfileInputAbility', () => {
    it('normalizesSubscriptionUrl', 0, () => {
      expect(normalizeProfileInput('  https://example.com/sub  ')).assertEqual('https://example.com/sub');
    });

    it('rejectsNonHttpSubscription', 0, () => {
      expect(isHttpSubscription('vless://node')).assertFalse();
    });
  });
}
