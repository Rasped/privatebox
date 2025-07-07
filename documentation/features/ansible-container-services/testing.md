# Testing Strategy for Ansible Container Services

## Overview

This document outlines how we'll verify that our Ansible container service deployments work correctly. We focus on practical, lightweight testing that can be run manually or automated through SemaphoreUI.

## Testing Levels

### 1. Pre-deployment Validation

**What**: Verify environment is ready for deployment
**When**: Before any service deployment
**How**: Built into each playbook's preflight checks

Tests:
- Podman is installed and accessible
- Required ports are available
- Sufficient disk space exists
- User has necessary permissions
- Network connectivity is available

Implementation:
```yaml
- name: Validate environment
  block:
    - name: Check Podman installation
      command: podman --version
      register: podman_version
      
    - name: Check available disk space
      shell: df -h {{ container_data_root }} | awk 'NR==2 {print $4}'
      register: disk_space
      
    - name: Verify minimum requirements
      assert:
        that:
          - podman_version.rc == 0
          - disk_space.stdout | regex_replace('G','') | int > 5
        fail_msg: "Environment validation failed"
```

### 2. Deployment Testing

**What**: Verify service deploys successfully
**When**: During each deployment
**How**: Built into playbooks with proper error handling

Tests:
- Quadlet file is valid syntax
- Systemd service starts successfully
- Container is running
- Health checks pass
- Ports are listening

Implementation:
```yaml
- name: Verify deployment
  block:
    - name: Check service status
      systemd:
        name: "{{ service_name }}-container.service"
      register: service_status
      
    - name: Verify container is running
      command: podman ps --filter "name={{ service_name }}"
      register: container_status
      
    - name: Check port is listening
      wait_for:
        port: "{{ service_port }}"
        timeout: 30
```

### 3. Functional Testing

**What**: Verify service works as expected
**When**: After deployment completes
**How**: Service-specific smoke tests

#### AdGuard Home Tests:
```yaml
- name: Test AdGuard Home functionality
  block:
    - name: Check web interface responds
      uri:
        url: "http://{{ ansible_host }}:{{ adguard_web_port }}"
        status_code: [200, 302]  # 302 if redirecting to setup
        
    - name: Test DNS resolution
      command: dig @{{ ansible_host }} -p {{ adguard_dns_port }} google.com
      register: dns_test
      failed_when: "'ANSWER SECTION' not in dns_test.stdout"
```

### 4. Integration Testing

**What**: Verify services work together
**When**: After deploying multiple services
**How**: Cross-service interaction tests

Tests:
- Services can communicate if needed
- No port conflicts
- Shared volumes work correctly
- Network isolation is proper

### 5. Update Testing

**What**: Verify updates work without data loss
**When**: Before rolling out updates
**How**: Dedicated update test playbook

Process:
1. Deploy service with test data
2. Create backup
3. Run update playbook
4. Verify data persists
5. Verify new version running
6. Test rollback procedure

## Manual Test Procedures

### Quick Smoke Test
After deploying any service, run:
```bash
# 1. Check service status
sudo systemctl status <service>-container.service

# 2. Check container logs
sudo podman logs <service>-container

# 3. Test service endpoint
curl -I http://localhost:<port>

# 4. Check resource usage
sudo podman stats --no-stream <service>-container
```

### SemaphoreUI Test Job

Create a test job template in SemaphoreUI:
- **Name**: "Test Container Services"
- **Playbook**: `playbooks/maintenance/test_services.yml`
- **Schedule**: After each deployment or nightly

## Continuous Monitoring

### Health Check Implementation

Each Quadlet file includes health checks:
```ini
HealthCmd=curl -f http://localhost:3000/health || exit 1
HealthInterval=30s
HealthRetries=3
HealthStartPeriod=60s
HealthTimeout=10s
```

### Monitoring Playbook
```yaml
---
- name: Monitor Container Services Health
  hosts: privatebox
  tasks:
    - name: Get all container services
      shell: systemctl list-units --type=service --all | grep container.service
      register: container_services
      
    - name: Check each service health
      systemd:
        name: "{{ item }}"
      loop: "{{ container_services.stdout_lines }}"
      register: health_results
      
    - name: Report unhealthy services
      debug:
        msg: "Service {{ item.item }} is unhealthy"
      loop: "{{ health_results.results }}"
      when: item.status.ActiveState != "active"
```

## Test Data Management

### Persistent Test Data
Create test fixtures that survive container restarts:
```yaml
- name: Create test data
  copy:
    content: |
      # Test configuration
      test_mode: true
      test_timestamp: {{ ansible_date_time.epoch }}
    dest: "{{ service_config_dir }}/test_marker.yml"
```

### Cleanup Procedures
```yaml
- name: Cleanup test artifacts
  file:
    path: "{{ item }}"
    state: absent
  loop:
    - "{{ service_config_dir }}/test_marker.yml"
    - "{{ service_data_dir }}/test_data"
  tags: [cleanup, never]
```

## Failure Scenarios

### What to Test:
1. **Port already in use**: Service should fail gracefully with clear error
2. **Insufficient permissions**: Should provide helpful error message
3. **Image pull failures**: Should retry with exponential backoff
4. **Config corruption**: Should detect and alert, not crash
5. **Disk full**: Should handle gracefully
6. **Network issues**: Should not hang indefinitely

### Recovery Testing:
```yaml
- name: Test recovery procedures
  block:
    - name: Stop service abruptly
      systemd:
        name: "{{ service_name }}-container.service"
        state: stopped
        
    - name: Corrupt config file
      lineinfile:
        path: "{{ service_config }}"
        line: "INVALID_SYNTAX{{{{"
        
    - name: Attempt service start
      systemd:
        name: "{{ service_name }}-container.service"
        state: started
      register: start_result
      failed_when: false
      
    - name: Verify error handling
      assert:
        that:
          - start_result.failed
          - "'config' in start_result.msg"
```

## Performance Testing

### Basic Performance Checks:
```yaml
- name: Measure service startup time
  block:
    - name: Stop service
      systemd:
        name: "{{ service_name }}-container.service"
        state: stopped
        
    - name: Record start time
      set_fact:
        start_time: "{{ ansible_date_time.epoch }}"
        
    - name: Start service
      systemd:
        name: "{{ service_name }}-container.service"
        state: started
        
    - name: Wait for service ready
      wait_for:
        port: "{{ service_port }}"
        
    - name: Calculate startup time
      set_fact:
        startup_duration: "{{ ansible_date_time.epoch | int - start_time | int }}"
        
    - name: Assert reasonable startup time
      assert:
        that:
          - startup_duration | int < 60
        fail_msg: "Service took {{ startup_duration }}s to start (>60s)"
```

## Test Reporting

### Generate Test Report:
```yaml
- name: Generate test report
  template:
    src: test_report.j2
    dest: "{{ privatebox_base_path }}/test_reports/{{ ansible_date_time.date }}_test_report.html"
  vars:
    test_results: "{{ all_test_results }}"
```

## Success Criteria

A deployment is considered successful when:
1. ✅ All preflight checks pass
2. ✅ Service starts without errors
3. ✅ Health checks pass within 60 seconds
4. ✅ Service endpoints respond correctly
5. ✅ No errors in container logs
6. ✅ Resource usage is within limits
7. ✅ Data persists across restarts