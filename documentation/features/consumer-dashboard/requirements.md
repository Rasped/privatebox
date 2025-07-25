# Consumer Dashboard Requirements

## User Stories

### As a Non-Technical User

1. **Service Discovery**
   - I want to browse available privacy services by category
   - I want to understand what each service does in plain language
   - I want to see system requirements before installing
   - I want to search for specific functionality

2. **Easy Installation**
   - I want to install services with one click
   - I want sensible defaults so I don't need to configure everything
   - I want clear progress indicators during installation
   - I want to know when something goes wrong in terms I understand

3. **Service Management**
   - I want to see all my installed services in one place
   - I want to start and stop services easily
   - I want to see if services are working properly
   - I want to access service interfaces with one click

4. **Resource Awareness**
   - I want to know if I have enough resources before installing
   - I want to see how much of my system each service uses
   - I want warnings before I run out of resources
   - I want suggestions for freeing up resources

### As a Family Administrator

1. **User Management**
   - I want to create accounts for family members
   - I want to control what services each person can use
   - I want to see who is using what
   - I want to set resource limits per user

2. **Privacy Controls**
   - I want to isolate certain services from others
   - I want to control network access per service
   - I want to see what data services can access
   - I want to audit service behavior

3. **Parental Controls**
   - I want to restrict children's access to certain services
   - I want to set time-based access rules
   - I want to monitor usage without being invasive
   - I want to gradually grant more access as children grow

### As a Power User

1. **Escape Hatches**
   - I want quick access to Semaphore when needed
   - I want to see raw logs when troubleshooting
   - I want to run custom Ansible playbooks
   - I want SSH access information readily available

2. **Advanced Configuration**
   - I want to override defaults when I know better
   - I want to see all configuration options
   - I want to edit service configurations directly
   - I want to create custom service templates

3. **Automation**
   - I want to schedule service updates
   - I want to create service dependencies
   - I want to automate backups
   - I want to integrate with external systems

## Functional Requirements

### Core Features

1. **Service Catalog**
   - Display available services with metadata
   - Categorize services (Privacy, Media, Storage, etc.)
   - Show resource requirements
   - Indicate compatibility and dependencies
   - Provide installation time estimates

2. **Installation Wizard**
   - Guide users through configuration
   - Validate inputs before proceeding
   - Show progress with time estimates
   - Handle errors gracefully
   - Provide rollback on failure

3. **Dashboard Home**
   - Show installed services with status
   - Display system resource usage
   - Highlight issues requiring attention
   - Provide quick actions per service
   - Show recent activity

4. **Service Management**
   - Start/stop services with confirmation
   - View service logs (filtered for relevance)
   - Update services with one click
   - Backup service data
   - Uninstall with data preservation options

5. **User Management**
   - Local user accounts (no external auth initially)
   - Role-based permissions (admin, user, restricted)
   - Service-level access control
   - Resource quotas per user
   - Activity audit trail

### Technical Requirements

1. **Performance**
   - Dashboard loads in <2 seconds
   - Status updates within 5 seconds
   - Support 100+ concurrent users
   - Handle 50+ installed services
   - Work on 5-year-old devices

2. **Compatibility**
   - Responsive design for all screen sizes
   - Work in modern browsers (Chrome, Firefox, Safari)
   - Function without JavaScript (basic features)
   - Accessible via screen readers
   - Support keyboard navigation

3. **Security**
   - HTTPS only with automatic certificates
   - Secure session management
   - No passwords in logs or URLs
   - Rate limiting on all endpoints
   - CSRF protection

4. **Reliability**
   - Graceful degradation if Semaphore unavailable
   - Queue operations during high load
   - Automatic retry with backoff
   - Clear timeout messages
   - Data consistency guarantees

5. **Privacy**
   - No telemetry or analytics
   - All data stored locally
   - No external service dependencies
   - Clear data retention policies
   - User data export capability

## Non-Functional Requirements

### Usability
- Grandmother-friendly interface
- Maximum 3 clicks to any feature
- Consistent visual language
- Contextual help available
- Undo for destructive actions

### Maintainability
- Single binary deployment
- Automatic database migrations
- Self-contained with no dependencies
- Clear upgrade path
- Rollback capability

### Scalability
- Support single-user to small business
- Efficient resource usage
- Horizontal scaling ready
- Database size management
- Log rotation built-in

### Internationalization
- English first, framework for others
- RTL language support ready
- Locale-aware formatting
- Translatable error messages
- Cultural sensitivity

## Constraints

### Technical Constraints
- Must work with existing Ansible playbooks
- Cannot require Semaphore modifications
- Must respect system resource limits
- Should not interfere with direct access
- Must maintain backward compatibility

### User Constraints
- No assumed technical knowledge
- No command line required
- No understanding of networking needed
- No Ansible/YAML knowledge required
- No Linux administration skills needed

### Business Constraints
- Open source (same license as PrivateBox)
- No subscription features
- No data lock-in
- No proprietary dependencies
- Community-maintainable

## Success Criteria

### Quantitative
- 90% of users can install first service without help
- <5% of installations fail due to UI issues
- 80% of errors are understood without documentation
- Page load times consistently <2 seconds
- 95% uptime for dashboard service

### Qualitative
- Users feel confident managing their services
- Error messages are helpful, not frustrating
- The interface feels modern but not trendy
- Power users don't feel constrained
- Family members can share without conflicts

## Out of Scope

The following are explicitly NOT requirements for the initial version:

1. **Not Included**
   - Service development SDK
   - Cloud backup integration  
   - Remote management capability
   - Clustering support
   - Advanced monitoring/alerting

2. **Future Considerations**
   - Mobile native apps
   - Voice control
   - AR/VR interfaces
   - AI-powered troubleshooting
   - Blockchain anything

## Dependencies

### On Existing Systems
- Semaphore API must remain stable
- Ansible playbooks must follow conventions
- Proxmox must be accessible via SSH
- Network configuration must be predictable
- Service containers must be well-behaved

### On Future Development
- Service catalog must be maintained
- Error patterns must be documented
- Resource requirements must be accurate
- Security updates must be timely
- Community must contribute services