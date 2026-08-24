import { describe, it, expect } from '@ohos/hypium';
import { isHttpSubscription, normalizeProfileInput } from '../main/ets/service/ProfileInput';

export default function profileInputTest() {
  describe('ProfileInput', () => {
    it('trimsScannedSubscription', 0, () => {
      expect(normalizeProfileInput('  https://example.com/sub  ')).assertEqual('https://example.com/sub');
    });

    it('keepsProxyScheme', 0, () => {
      expect(normalizeProfileInput('vless://node')).assertEqual('vless://node');
    });

    it('acceptsHttpSubscription', 0, () => {
      expect(isHttpSubscription('HTTPS://example.com/config')).assertTrue();
    });

    it('rejectsSingleProxyAsSubscription', 0, () => {
      expect(isHttpSubscription('ss://node')).assertFalse();
    });
  });
}
