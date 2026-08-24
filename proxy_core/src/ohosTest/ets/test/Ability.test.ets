import { describe, it, expect } from '@ohos/hypium';
import { isProxyGroup, ProxyType } from '../../../main/ets/models/Proxy';
import { RpcMethod, RPC_EOF } from '../../../main/ets/core/RpcProtocol';

export default function proxyContractAbilityTest() {
  describe('ProxyContractAbility', () => {
    it('recognizesSelector', 0, () => {
      expect(isProxyGroup(ProxyType.Selector)).assertTrue();
      expect(isProxyGroup(ProxyType.Direct)).assertFalse();
    });

    it('keepsFrameAndMethodStable', 0, () => {
      expect(RPC_EOF).assertEqual('EOF');
      expect(RpcMethod.StartClash).assertEqual(13);
    });
  });
}
