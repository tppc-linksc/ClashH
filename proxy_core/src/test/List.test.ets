import { describe, it, expect } from '@ohos/hypium';
import { isProxyGroup, ProxyType } from '../main/ets/models/Proxy';
import { RpcMethod, RPC_EOF } from '../main/ets/core/RpcProtocol';

export default function proxyCoreContractTest() {
  describe('ProxyCoreContract', () => {
    it('recognizesSelectableGroups', 0, () => {
      expect(isProxyGroup(ProxyType.Selector)).assertTrue();
      expect(isProxyGroup(ProxyType.Direct)).assertFalse();
    });

    it('keepsRpcMethodValuesStable', 0, () => {
      expect(RpcMethod.StartClash).assertEqual(13);
      expect(RpcMethod.GetVersion).assertEqual(33);
    });

    it('usesNonEmptyFrameDelimiter', 0, () => {
      expect(RPC_EOF.length).assertLarger(0);
    });
  });
}
