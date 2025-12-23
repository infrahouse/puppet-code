# Compliance Logging Rollout Plan

## Progress Tracker

### Prerequisites
- [x] Base auditd profile created (`modules/profile/manifests/auditd.pp`)
- [x] Base audit configuration templates
  - [x] `auditd.conf.erb`
  - [x] `base.rules.erb` (buffer: 65536, rate: unlimited)
  - [x] `compliance.rules.erb`
  - [x] `logrotate.erb`
- [x] Fix audit event loss issues (buffer/rate limits)

### Phase 1: Jumphost
#### 1.1 Development Environment
- [x] Create `jumphost/auditd.pp` profile
- [x] Create `jumphost.rules.erb` template
- [x] Create `jumphost/cloudwatch_agent.pp`
- [x] Create CloudWatch agent config template
- [x] Fix CloudWatch ACL permissions for audit logs
- [x] Deploy to dev jumphost
- [x] Validate audit rules: `sudo auditctl -l`
- [x] Test SSH session logging
- [x] Verify logs in `/var/log/audit/audit.log`
- [x] **Release**: `puppet-jumphost-auditd-dev-v1.0.0`

#### 1.2 Sandbox Environment
- [x] Copy configuration to sandbox
- [x] Deploy to sandbox jumphost
- [x] Run compliance validation
- [x] Performance impact assessment
- [x] **Release**: `puppet-jumphost-auditd-sandbox-v1.0.0`

#### 1.3 Global Modules (Production)
- [x] Move to global modules
- [x] Remove environment-specific versions
- [x] Deploy to production jumphost
- [x] **Release**: `puppet-jumphost-auditd-prod-v1.0.0`

### Phase 2: Terraformer
#### 2.1 Development Environment
- [ ] Create `terraformer/auditd.pp`
- [ ] Create `terraformer.rules.erb`
- [ ] Testing and validation
- [ ] **Release**: `puppet-terraformer-auditd-dev-v1.0.0`

#### 2.2 Sandbox Environment
- [ ] Deploy to sandbox
- [ ] Infrastructure change simulations
- [ ] **Release**: `puppet-terraformer-auditd-sandbox-v1.0.0`

#### 2.3 Global Modules (Production)
- [ ] Deploy to production
- [ ] **Release**: `puppet-terraformer-auditd-prod-v1.0.0`

### Phase 3: Elasticsearch
#### 3.1 Development Environment
- [ ] Create `elastic/auditd.pp`
- [ ] Create `elastic/cloudwatch_agent.pp`
- [ ] Create templates
- [ ] Deploy to single ES node
- [ ] **Release**: `puppet-elastic-auditd-dev-v1.0.0`

#### 3.2 Sandbox Environment
- [ ] Deploy to sandbox cluster
- [ ] Load testing
- [ ] CloudWatch cost analysis
- [ ] **Release**: `puppet-elastic-auditd-sandbox-v1.0.0`

#### 3.3 Global Modules (Production)
- [ ] Phased rollout (data nodes → master nodes)
- [ ] **Release**: `puppet-elastic-auditd-prod-v1.0.0`

### Phase 4: CloudWatch Integration
- [ ] Add CloudWatch to all roles
- [ ] Create dashboards
- [ ] Set up alarms

### Phase 5: Additional Roles
- [ ] openvpn_server
- [ ] github_runner
- [ ] webserver
- [ ] mta

### Phase 6: Compliance Automation
- [ ] Automated compliance reports
- [ ] CloudWatch Insights queries
- [ ] Monthly audit reviews

---

## Overview
Phased implementation of SOC2/ISO27001 compliant logging across infrastructure roles using auditd and CloudWatch.

## Rollout Strategy
- **One role at a time**: Minimize risk, validate each implementation
- **Environment progression**: development → sandbox → production (global modules)
- **Separate releases**: Each role+environment gets its own release/commit
- **Testing between phases**: Validate before proceeding

## Phase Structure
Each phase follows this pattern:
1. Development environment (test with limited nodes)
2. Sandbox environment (broader testing)
3. Global modules (production-ready)

---

## PHASE 1: JUMPHOST (Critical - Highest Risk Asset)

### Why Jumphost First?
- Highest security risk (privileged access point)
- Limited number of instances (easier to rollback)
- Most comprehensive audit requirements
- Good test case for the base auditd profile

### 1.1 Development Environment
**Files to create**:
```
environments/development/modules/profile/manifests/jumphost/
└── auditd.pp

environments/development/modules/profile/templates/jumphost/
└── jumphost.rules.erb
```

**Implementation**:
- Create jumphost-specific auditd profile
- Include base auditd from global modules
- Enhanced SSH session monitoring
- Outbound connection tracking
- File transfer monitoring
- Comprehensive command execution audit

**Testing**:
- Deploy to dev jumphost
- Verify audit rules loaded: `sudo auditctl -l`
- Test SSH sessions generate logs
- Confirm logs appear in `/var/log/audit/audit.log`

**Release**: `puppet-jumphost-auditd-dev-v1.0.0`

### 1.2 Sandbox Environment
**Files to create**:
```
environments/sandbox/modules/profile/manifests/jumphost/
└── auditd.pp

environments/sandbox/modules/profile/templates/jumphost/
└── jumphost.rules.erb
```

**Implementation**:
- Copy from development (if successful)
- Any sandbox-specific adjustments

**Testing**:
- Deploy to sandbox jumphost
- Run compliance validation scripts
- Performance impact assessment

**Release**: `puppet-jumphost-auditd-sandbox-v1.0.0`

### 1.3 Global Modules (Production)
**Files to create**:
```
modules/profile/manifests/jumphost/
└── auditd.pp

modules/profile/templates/jumphost/
└── jumphost.rules.erb
```

**Implementation**:
- Move tested configuration to global modules
- Remove environment-specific versions
- Update role manifest to include

**Release**: `puppet-jumphost-auditd-prod-v1.0.0`

### 1.4 CloudWatch Integration (Optional - Separate Phase)
**Files to create**:
```
modules/profile/manifests/jumphost/
└── cloudwatch_agent.pp

modules/profile/templates/jumphost/
└── amazon-cloudwatch-agent.json.erb
```

**Note**: Can be done after all auditd phases complete

---

## PHASE 2: TERRAFORMER (Infrastructure Changes)

### Why Terraformer Second?
- Critical for change management compliance
- Limited instances
- Clear audit requirements (infrastructure changes)

### 2.1 Development Environment
**Files to create**:
```
environments/development/modules/profile/manifests/terraformer/
└── auditd.pp

environments/development/modules/profile/templates/terraformer/
└── terraformer.rules.erb
```

**Implementation**:
- Terraform execution monitoring
- State file access tracking
- AWS CLI monitoring
- Git operations tracking
- CI/CD integration monitoring

**Testing**:
- Run terraform commands
- Verify audit trail generated
- Check state file access logged

**Release**: `puppet-terraformer-auditd-dev-v1.0.0`

### 2.2 Sandbox Environment
**Files to create**:
```
environments/sandbox/modules/profile/manifests/terraformer/
└── auditd.pp

environments/sandbox/modules/profile/templates/terraformer/
└── terraformer.rules.erb
```

**Testing**:
- Infrastructure change simulations
- Validate change tracking

**Release**: `puppet-terraformer-auditd-sandbox-v1.0.0`

### 2.3 Global Modules (Production)
**Files to create**:
```
modules/profile/manifests/terraformer/
└── auditd.pp

modules/profile/templates/terraformer/
└── terraformer.rules.erb
```

**Release**: `puppet-terraformer-auditd-prod-v1.0.0`

---

## PHASE 3: ELASTICSEARCH (Largest Deployment)

### Why Elasticsearch Last?
- Most complex implementation
- Largest number of instances
- Needs both auditd AND CloudWatch
- Highest risk if something goes wrong

### 3.1 Development Environment
**Files to create**:
```
environments/development/modules/profile/manifests/elastic/
├── auditd.pp
└── cloudwatch_agent.pp

environments/development/modules/profile/templates/elastic/
├── elasticsearch.rules.erb
└── amazon-cloudwatch-agent.json.erb
```

**Implementation**:
- Elasticsearch-specific audit rules
- Data directory monitoring
- Configuration change tracking
- CloudWatch agent with all log streams
- Metrics collection

**Testing**:
- Deploy to single ES node first
- Verify no performance impact
- Test log shipping to CloudWatch
- Validate multiline log handling

**Release**: `puppet-elastic-auditd-dev-v1.0.0`

### 3.2 Sandbox Environment
**Files to create**:
```
environments/sandbox/modules/profile/manifests/elastic/
├── auditd.pp
└── cloudwatch_agent.pp

environments/sandbox/modules/profile/templates/elastic/
├── elasticsearch.rules.erb
└── amazon-cloudwatch-agent.json.erb
```

**Testing**:
- Deploy to full sandbox cluster
- Load testing with audit enabled
- CloudWatch cost analysis

**Release**: `puppet-elastic-auditd-sandbox-v1.0.0`

### 3.3 Global Modules (Production)
**Files to create**:
```
modules/profile/manifests/elastic/
├── auditd.pp
└── cloudwatch_agent.pp

modules/profile/templates/elastic/
├── elasticsearch.rules.erb
└── amazon-cloudwatch-agent.json.erb
```

**Rollout Strategy**:
- Deploy to one data node first
- Monitor for 24 hours
- Deploy to remaining data nodes
- Deploy to master nodes last

**Release**: `puppet-elastic-auditd-prod-v1.0.0`

---

## Prerequisites

### Base Auditd Profile (Required First)
**Files to create in global modules**:
```
modules/profile/manifests/
└── auditd.pp

modules/profile/templates/auditd/
├── auditd.conf.erb
├── base.rules.erb
├── compliance.rules.erb
└── logrotate.erb
```

**This must be created first as all role-specific profiles depend on it**

---

## Testing Protocol

### For Each Phase:
1. **Pre-deployment**:
   - Review Puppet code with `puppet-lint`
   - Dry-run with `--noop`
   - Review proposed changes

2. **Deployment**:
   - Deploy to single node
   - Monitor for 30 minutes
   - Check system resources
   - Verify audit rules active

3. **Validation**:
   - Generate test events
   - Verify logs created
   - Check log rotation
   - Confirm no performance degradation

4. **Rollback Plan**:
   - Keep previous version in git
   - Document rollback procedure
   - Test rollback in dev first

---

## Success Criteria

### Per Phase:
- ✓ Audit rules loaded successfully
- ✓ Logs generated for test events
- ✓ No performance impact (< 2% CPU increase)
- ✓ No Puppet errors
- ✓ Log rotation working

### Overall:
- ✓ SOC2 compliance requirements met
- ✓ ISO27001 controls implemented
- ✓ Incident response capabilities validated
- ✓ No production incidents

---

## Risk Mitigation

### Risks:
1. **Performance impact**: High audit volume could impact system
   - Mitigation: Rate limiting, buffer tuning

2. **Disk space**: Audit logs could fill disk
   - Mitigation: Log rotation, monitoring

3. **Service disruption**: Auditd issues could affect system
   - Mitigation: Phased rollout, testing

4. **Configuration conflicts**: Existing configs might conflict
   - Mitigation: Environment testing first

---

## Timeline

### Estimated Schedule:
- **Week 1**: Base auditd profile + Jumphost Development
- **Week 2**: Jumphost Sandbox + Production
- **Week 3**: Terraformer (all environments)
- **Week 4**: Elasticsearch Development
- **Week 5**: Elasticsearch Sandbox
- **Week 6**: Elasticsearch Production rollout

### Hold Points:
- After each environment deployment
- Before production deployments
- If any issues discovered

---

## Communication Plan

### Stakeholders:
- Security team: Full visibility
- Operations team: Performance monitoring
- Compliance team: Implementation updates
- Development team: Testing requirements

### Updates:
- Daily during active deployment
- Weekly status reports
- Immediate notification of issues

---

## Post-Implementation

### Phase 4: CloudWatch Integration (After Core Auditd)
- Add CloudWatch agents to all roles
- Centralized log analysis
- Create CloudWatch dashboards
- Set up alarms

### Phase 5: Additional Roles
Following the same pattern:
- `openvpn_server`
- `github_runner`
- `webserver`
- `mta`
- etc.

### Phase 6: Compliance Automation
- Automated compliance reports
- CloudWatch Insights queries
- Monthly audit reviews
- Annual compliance validation

---

## Rollback Procedures

### If Issues in Development:
1. Remove role-specific includes from node manifests
2. Run Puppet to remove configurations
3. Review and fix issues
4. Re-test in isolated environment

### If Issues in Sandbox/Production:
1. Revert git commit
2. Trigger Puppet run with previous version
3. Verify audit rules removed: `sudo auditctl -l`
4. Document issue for resolution

---

## Documentation Requirements

### For Each Phase:
- Update README with new profiles
- Document testing results
- Record performance metrics
- Update compliance mapping

### Final Documentation:
- Complete compliance guide
- Operational runbook
- Troubleshooting guide
- Query library for investigations