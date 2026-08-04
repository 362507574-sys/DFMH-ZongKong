const LEVELS = [
  ['artifact', 'artifactChecks'],
  ['skill', 'skillChecks'],
  ['cross-skill', 'crossSkillChecks'],
  ['organization-chain', 'chainChecks'],
];

export function evaluateOrganizationQuality(input = {}) {
  const levels = LEVELS.map(([name, field]) => {
    const checks = input[field] ?? [];
    const passed = checks.length === 0 || checks.every((check) => check?.passed === true);
    return Object.freeze({
      name,
      status: passed ? 'passed' : 'failed',
      checks: Object.freeze(structuredClone(checks)),
    });
  });
  const readiness = Object.freeze({
    evidenceReady: input.evidenceReady === true,
    versionBindingsReady: input.versionBindingsReady === true,
    decisionBoundaryReady: input.decisionBoundaryReady === true,
    returnPackageReady: input.returnPackageReady === true,
  });
  const failures = [
    ...levels.filter((level) => level.status === 'failed').map((level) => level.name),
    ...Object.entries(readiness).filter(([, ready]) => !ready).map(([name]) => name),
  ];
  return Object.freeze({
    schemaVersion: 2,
    ok: failures.length === 0,
    levels: Object.freeze(levels),
    readiness,
    failures: Object.freeze(failures),
  });
}
