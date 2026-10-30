/** 国内直连规则注入结果，便于调用方记录实际修改。 */
export interface DomesticDirectRulesResult {
  rules: string[];
  insertedRules: string[];
  uncertainChinaRuleSet: boolean;
}

interface ParsedRule {
  category: string;
  isDomestic: boolean;
  isChinaRuleSet: boolean;
  isDirect: boolean;
  isFallback: boolean;
}

const GENERATED_RULES: string[] = [
  'DOMAIN-SUFFIX,cn,DIRECT',
  'GEOSITE,cn,DIRECT',
  'GEOIP,CN,DIRECT'
];

/**
 * 在配置中的宽泛国内分类规则之前补齐 DIRECT 规则。
 * 更靠前的具体 DOMAIN/DOMAIN-KEYWORD 规则保留原有优先级。
 */
export function applyDomesticDirectRules(sourceRules: string[]): DomesticDirectRulesResult {
  const rules = sourceRules.slice();
  const parsedRules: ParsedRule[] = rules.map((rule: string) =>
    parseRule(typeof rule === 'string' ? rule : ''));
  let fallbackIndex = rules.length;
  let firstDomesticIndex = rules.length;
  let uncertainChinaRuleSet = false;
  const directSeen: Record<string, boolean> = {
    'DOMAIN-SUFFIX': false,
    'GEOSITE': false,
    'GEOIP': false
  };
  const blocked: Record<string, boolean> = {
    'DOMAIN-SUFFIX': false,
    'GEOSITE': false,
    'GEOIP': false
  };

  for (let i = 0; i < parsedRules.length; i++) {
    const parsed = parsedRules[i];
    if (parsed.isFallback && fallbackIndex === rules.length) {
      fallbackIndex = i;
    }
    if (parsed.isChinaRuleSet) {
      uncertainChinaRuleSet = true;
      if (i < fallbackIndex && firstDomesticIndex === rules.length) {
        firstDomesticIndex = i;
      }
      if (i < fallbackIndex) {
        directSeen['DOMAIN-SUFFIX'] = false;
        directSeen['GEOSITE'] = false;
        directSeen['GEOIP'] = false;
        blocked['DOMAIN-SUFFIX'] = true;
        blocked['GEOSITE'] = true;
        blocked['GEOIP'] = true;
      }
    }
    if (!parsed.isDomestic) {
      continue;
    }
    if (i < fallbackIndex && firstDomesticIndex === rules.length) {
      firstDomesticIndex = i;
    }
    if (parsed.category.length === 0 || i >= fallbackIndex) {
      continue;
    }
    if (!blocked[parsed.category]) {
      if (parsed.isDirect) {
        directSeen[parsed.category] = true;
      } else {
        blocked[parsed.category] = true;
      }
    }
  }

  const missingRules: string[] = [];
  for (let i = 0; i < GENERATED_RULES.length; i++) {
    const generated = GENERATED_RULES[i];
    const category = generated.split(',')[0];
    if (!directSeen[category]) {
      missingRules.push(generated);
    }
  }
  if (missingRules.length === 0) {
    return { rules, insertedRules: [], uncertainChinaRuleSet };
  }

  const insertAt = firstDomesticIndex < fallbackIndex ? firstDomesticIndex : fallbackIndex;
  rules.splice(insertAt, 0, ...missingRules);
  return { rules, insertedRules: missingRules, uncertainChinaRuleSet };
}

function parseRule(rule: string): ParsedRule {
  const fields: string[] = rule.split(',').map((field: string) => field.trim().toUpperCase());
  const type = fields.length > 0 ? fields[0] : '';
  const value = fields.length > 1 ? fields[1] : '';
  const isDirect = fields.length > 2 && fields[2] === 'DIRECT';
  const isFallback = type === 'MATCH' || type === 'FINAL';
  const isDomestic = (type === 'DOMAIN-SUFFIX' && value === 'CN') ||
    ((type === 'GEOSITE' || type === 'GEOIP') && value === 'CN');
  const setName = type === 'RULE-SET' ? value.replace(/[^A-Z0-9]/g, '') : '';
  const isChinaRuleSet = type === 'RULE-SET' &&
    (setName.indexOf('CN') >= 0 || setName.indexOf('CHINA') >= 0);
  const category = isDomestic ? type : '';
  return { category, isDomestic, isChinaRuleSet, isDirect, isFallback };
}
