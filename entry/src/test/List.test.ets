import { describe, it, expect } from '@ohos/hypium';
import { isHttpSubscription, normalizeProfileInput } from '../main/ets/service/ProfileInput';
import { applyDomesticDirectRules } from '../main/ets/service/DomesticDirectRules';
import { convertShareLinks } from '../main/ets/service/ShareLinkParser';

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

  describe('ShareLinkParser', () => {
    it('keepsAllowInsecureForVless', 0, () => {
      // 机场常用「借用域名做 SNI + 自签证书」，allowInsecure=1 必须落成 skip-cert-verify，
      // 否则内核严格校验证书，所有 vless 节点握手失败、测速全超时。
      const result = convertShareLinks(
        'vless://11111111-2222-3333-4444-555555555555@hk1.example.com:443' +
        '?allowInsecure=1&encryption=none&flow=xtls-rprx-vision&security=tls&sni=baidu.com&type=tcp#香港 01');
      expect(result.count).assertEqual(1);
      expect(result.yaml.indexOf('"skip-cert-verify":true') >= 0).assertTrue();
      expect(result.yaml.indexOf('"servername":"baidu.com"') >= 0).assertTrue();
    });

    it('fallsBackToPeerForTrojanServername', 0, () => {
      const result = convertShareLinks(
        'trojan://secret@us1.example.com:443?allowInsecure=1&peer=update.microsoft.com&type=tcp#美国 01');
      expect(result.yaml.indexOf('"sni":"update.microsoft.com"') >= 0).assertTrue();
      expect(result.yaml.indexOf('"skip-cert-verify":true') >= 0).assertTrue();
    });
  });

  describe('DomesticDirectRules', () => {
    it('placesDirectRulesBeforeChinaProxyRulesAndKeepsSpecificRules', 0, () => {
      const result = applyDomesticDirectRules([
        'DOMAIN,api.example.cn,PROXY',
        'GEOSITE,CN,PROXY',
        'MATCH,GLOBAL'
      ]);
      expect(result.rules[0]).assertEqual('DOMAIN,api.example.cn,PROXY');
      expect(result.rules[1]).assertEqual('DOMAIN-SUFFIX,cn,DIRECT');
      expect(result.rules[2]).assertEqual('GEOSITE,cn,DIRECT');
      expect(result.rules[3]).assertEqual('GEOIP,CN,DIRECT');
      expect(result.rules[4]).assertEqual('GEOSITE,CN,PROXY');
    });

    it('doesNotDuplicateCompleteDirectCoverage', 0, () => {
      const source = [
        'DOMAIN-SUFFIX,cn,DIRECT',
        'GEOSITE,CN,DIRECT',
        'GEOIP,CN,DIRECT',
        'MATCH,GLOBAL'
      ];
      const result = applyDomesticDirectRules(source);
      expect(result.insertedRules.length).assertEqual(0);
      expect(result.rules.length).assertEqual(source.length);
    });

    it('acceptsWhitespaceAndCaseAndAddsOnlyMissingCoverage', 0, () => {
      const result = applyDomesticDirectRules([
        'GEOSITE , cn , direct',
        'GEOIP,CN,PROXY',
        'MATCH,GLOBAL'
      ]);
      expect(result.insertedRules.length).assertEqual(2);
      expect(result.rules[0]).assertEqual('DOMAIN-SUFFIX,cn,DIRECT');
      expect(result.rules[1]).assertEqual('GEOIP,CN,DIRECT');
      expect(result.rules[2]).assertEqual('GEOSITE , cn , direct');
    });

    it('placesRulesBeforeChinaRuleSetsAndReportsAmbiguity', 0, () => {
      const result = applyDomesticDirectRules([
        'DOMAIN,portal.example.cn,PROXY',
        'RULE-SET,geolocation-cn,PROXY',
        'MATCH,GLOBAL'
      ]);
      expect(result.rules[0]).assertEqual('DOMAIN,portal.example.cn,PROXY');
      expect(result.rules[1]).assertEqual('DOMAIN-SUFFIX,cn,DIRECT');
      expect(result.rules[4]).assertEqual('RULE-SET,geolocation-cn,PROXY');
      expect(result.uncertainChinaRuleSet).assertTrue();
    });
  });
}
