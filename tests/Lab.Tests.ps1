#Requires -Modules Pester
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Pester tests that validate the Windows Hybrid Lab post-deployment state.

.DESCRIPTION
    Runs on HOUSTONDC1 (or any domain-joined DC) after the full lab is configured.
    Validates AD forest health, DC roles, DNS, replication, forest trust, and
    security baseline settings.

    Tests that require cross-forest connectivity are gated behind the
    $SkipCrossForest variable so you can run a partial suite before the
    trust is established.

.EXAMPLE
    # Run all tests (both forests must be operational):
    Invoke-Pester .\tests\Lab.Tests.ps1

    # Skip cross-forest tests:
    $SkipCrossForest = $true
    Invoke-Pester .\tests\Lab.Tests.ps1

.NOTES
    Target VM  : HOUSTONDC1 (preferred) or any lab.local DC
    Prereqs    : AD DS, DNS, Pester v5+, completed post-deploy checklist
    Install    : Install-Module Pester -Force -SkipPublisherCheck
#>

# ── Configuration ──────────────────────────────────────────────────────
$HoustonDomain  = 'lab.local'
$WestDomain     = 'west.lab.local'
$HoustonDC1     = 'HOUSTONDC1'
$HoustonDC2     = 'HOUSTONDC2'
$WestDC1        = 'WESTDC1'
$HoustonDC1Ip   = '10.20.1.10'
$HoustonDC2Ip   = '10.20.1.11'
$WestDC1Ip      = '10.30.1.10'
$MemberServers  = @('HOUSTONVM1', 'HOUSTONVM2')

if (-not (Get-Variable -Name SkipCrossForest -Scope Global -ErrorAction SilentlyContinue)) {
    $Global:SkipCrossForest = $false
}

# ═══════════════════════════════════════════════════════════════════════
# 1. AD Forest Health
# ═══════════════════════════════════════════════════════════════════════

Describe 'AD Forest Health' {

    Context 'Houston forest (lab.local)' {
        It 'Houston forest exists and is reachable' {
            $forest = Get-ADForest -Identity $HoustonDomain
            $forest.Name | Should -Be 'lab'
        }

        It 'Houston domain functional level is Windows2016 or higher' {
            $domain = Get-ADDomain -Identity $HoustonDomain
            $domain.DomainMode | Should -BeIn @(
                'Windows2016Domain', 'Windows2025Domain',
                'UnknownDomainMode'    # future-proof
            )
        }

        It 'Houston forest functional level is Windows2016 or higher' {
            $forest = Get-ADForest -Identity $HoustonDomain
            $forest.ForestMode | Should -BeIn @(
                'Windows2016Forest', 'Windows2025Forest',
                'UnknownForestMode'
            )
        }
    }

    Context 'West forest (west.lab.local)' -Skip:$SkipCrossForest {
        It 'West forest exists and is reachable' {
            $forest = Get-ADForest -Identity $WestDomain
            $forest.Name | Should -Be 'west'
        }

        It 'West domain functional level is Windows2016 or higher' {
            $domain = Get-ADDomain -Identity $WestDomain
            $domain.DomainMode | Should -BeIn @(
                'Windows2016Domain', 'Windows2025Domain',
                'UnknownDomainMode'
            )
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════
# 2. Domain Controller Health
# ═══════════════════════════════════════════════════════════════════════

Describe 'Domain Controller Health' {

    Context 'Houston DCs' {
        It 'HOUSTONDC1 is a domain controller' {
            $dc = Get-ADDomainController -Identity $HoustonDC1
            $dc | Should -Not -BeNullOrEmpty
        }

        It 'HOUSTONDC1 is a writable DC (not RODC)' {
            $dc = Get-ADDomainController -Identity $HoustonDC1
            $dc.IsReadOnly | Should -BeFalse
        }

        It 'HOUSTONDC2 is a domain controller' {
            $dc = Get-ADDomainController -Identity $HoustonDC2
            $dc | Should -Not -BeNullOrEmpty
        }

        It 'SYSVOL share is accessible on HOUSTONDC1' {
            Test-Path "\\$HoustonDC1\SYSVOL" | Should -BeTrue
        }

        It 'NETLOGON share is accessible on HOUSTONDC1' {
            Test-Path "\\$HoustonDC1\NETLOGON" | Should -BeTrue
        }

        It 'SYSVOL share is accessible on HOUSTONDC2' {
            Test-Path "\\$HoustonDC2\SYSVOL" | Should -BeTrue
        }
    }

    Context 'West DCs' -Skip:$SkipCrossForest {
        It 'WESTDC1 is a domain controller' {
            $dc = Get-ADDomainController -Identity $WestDC1 -Server $WestDomain
            $dc | Should -Not -BeNullOrEmpty
        }

        It 'WESTDC1 is a writable DC' {
            $dc = Get-ADDomainController -Identity $WestDC1 -Server $WestDomain
            $dc.IsReadOnly | Should -BeFalse
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════
# 3. DNS Resolution
# ═══════════════════════════════════════════════════════════════════════

Describe 'DNS Resolution' {

    Context 'Houston forward lookups' {
        It 'Resolves HOUSTONDC1.lab.local' {
            $result = Resolve-DnsName -Name "$HoustonDC1.$HoustonDomain" -Type A -ErrorAction Stop
            $result.IPAddress | Should -Contain $HoustonDC1Ip
        }

        It 'Resolves HOUSTONDC2.lab.local' {
            $result = Resolve-DnsName -Name "$HoustonDC2.$HoustonDomain" -Type A -ErrorAction Stop
            $result.IPAddress | Should -Contain $HoustonDC2Ip
        }
    }

    Context 'Houston reverse lookups' {
        It 'Reverse lookup for 10.20.1.10 returns HOUSTONDC1' {
            $result = Resolve-DnsName -Name $HoustonDC1Ip -Type PTR -ErrorAction Stop
            $result.NameHost | Should -Match $HoustonDC1
        }

        It 'Reverse lookup for 10.20.1.11 returns HOUSTONDC2' {
            $result = Resolve-DnsName -Name $HoustonDC2Ip -Type PTR -ErrorAction Stop
            $result.NameHost | Should -Match $HoustonDC2
        }
    }

    Context 'Cross-forest DNS' -Skip:$SkipCrossForest {
        It 'Houston can resolve WESTDC1.west.lab.local' {
            $result = Resolve-DnsName -Name "$WestDC1.$WestDomain" -Type A -ErrorAction Stop
            $result.IPAddress | Should -Contain $WestDC1Ip
        }

        It 'Conditional forwarder zone exists for west.lab.local' {
            $zone = Get-DnsServerZone -Name $WestDomain -ErrorAction SilentlyContinue
            $zone | Should -Not -BeNullOrEmpty
            $zone.ZoneType | Should -Be 'Forwarder'
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════
# 4. Replication Health
# ═══════════════════════════════════════════════════════════════════════

Describe 'Replication Health' {

    Context 'Houston intra-site replication' {
        It 'repadmin /replsummary reports no failures' {
            $output = repadmin /replsummary /bysrc /errorsonly 2>&1
            $joinedOutput = $output -join "`n"
            # If errorsonly returns no DC entries, replication is clean
            $joinedOutput | Should -Not -Match 'failed'
        }

        It 'HOUSTONDC2 has replicated from HOUSTONDC1 within the last 60 minutes' {
            $partners = Get-ADReplicationPartnerMetadata -Target $HoustonDC2 -ErrorAction Stop
            $recent = $partners | Where-Object { $_.LastReplicationSuccess -gt (Get-Date).AddMinutes(-60) }
            $recent | Should -Not -BeNullOrEmpty
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════
# 5. Forest Trust
# ═══════════════════════════════════════════════════════════════════════

Describe 'Forest Trust' -Skip:$SkipCrossForest {

    It 'Bidirectional trust exists between lab.local and west.lab.local' {
        $trust = Get-ADTrust -Filter { Target -eq 'west.lab.local' } -ErrorAction Stop
        $trust | Should -Not -BeNullOrEmpty
        $trust.Direction | Should -Be 'BiDirectional'
    }

    It 'Trust type is Forest' {
        $trust = Get-ADTrust -Filter { Target -eq 'west.lab.local' } -ErrorAction Stop
        $trust.ForestTransitive | Should -BeTrue
    }

    It 'Secure channel to west.lab.local is healthy' {
        $result = nltest /sc_verify:west.lab.local 2>&1
        $joinedResult = $result -join "`n"
        $joinedResult | Should -Match 'NERR_Success'
    }
}

# ═══════════════════════════════════════════════════════════════════════
# 6. Security Baseline
# ═══════════════════════════════════════════════════════════════════════

Describe 'Security Baseline' {

    Context 'Domain password policy' {
        BeforeAll {
            $policy = Get-ADDefaultDomainPasswordPolicy -Identity $HoustonDomain
        }

        It 'Minimum password length is 12' {
            $policy.MinPasswordLength | Should -Be 12
        }

        It 'Password history count is 24' {
            $policy.PasswordHistoryCount | Should -Be 24
        }

        It 'Maximum password age is 90 days' {
            $policy.MaxPasswordAge.Days | Should -Be 90
        }

        It 'Complexity is enabled' {
            $policy.ComplexityEnabled | Should -BeTrue
        }

        It 'Lockout threshold is 5 attempts' {
            $policy.LockoutThreshold | Should -Be 5
        }
    }

    Context 'Group Policy Objects' {
        It 'SEC - Audit Policy GPO exists' {
            $gpo = Get-GPO -Name 'SEC - Audit Policy' -ErrorAction SilentlyContinue
            $gpo | Should -Not -BeNullOrEmpty
        }

        It 'SEC - Firewall Baseline GPO exists' {
            $gpo = Get-GPO -Name 'SEC - Firewall Baseline' -ErrorAction SilentlyContinue
            $gpo | Should -Not -BeNullOrEmpty
        }

        It 'SEC - Disable SMBv1 GPO exists' {
            $gpo = Get-GPO -Name 'SEC - Disable SMBv1' -ErrorAction SilentlyContinue
            $gpo | Should -Not -BeNullOrEmpty
        }

        It 'GPOs are linked to domain root' {
            $links = (Get-GPInheritance -Target "DC=lab,DC=local").GpoLinks
            $linkNames = $links.DisplayName
            $linkNames | Should -Contain 'SEC - Audit Policy'
            $linkNames | Should -Contain 'SEC - Firewall Baseline'
            $linkNames | Should -Contain 'SEC - Disable SMBv1'
        }
    }

    Context 'Group Managed Service Accounts' {
        It 'svc-WebApp gMSA exists in lab.local' {
            $gmsa = Get-ADServiceAccount -Identity 'svc-WebApp' -ErrorAction SilentlyContinue
            $gmsa | Should -Not -BeNullOrEmpty
        }

        It 'svc-WebApp has principals allowed to retrieve password' {
            $gmsa = Get-ADServiceAccount -Identity 'svc-WebApp' -Properties PrincipalsAllowedToRetrieveManagedPassword
            $gmsa.PrincipalsAllowedToRetrieveManagedPassword | Should -Not -BeNullOrEmpty
        }
    }

    Context 'AD Sites & Subnets' {
        It 'Houston site exists' {
            $site = Get-ADReplicationSite -Identity 'Houston' -ErrorAction SilentlyContinue
            $site | Should -Not -BeNullOrEmpty
        }

        It 'West site exists' {
            $site = Get-ADReplicationSite -Identity 'West' -ErrorAction SilentlyContinue
            $site | Should -Not -BeNullOrEmpty
        }

        It 'Houston subnet is mapped to Houston site' {
            $subnet = Get-ADReplicationSubnet -Identity '10.20.1.0/24' -ErrorAction SilentlyContinue
            $subnet | Should -Not -BeNullOrEmpty
            $subnet.Site | Should -Match 'Houston'
        }

        It 'Inter-site link Houston-West exists' {
            $link = Get-ADReplicationSiteLink -Identity 'Houston-West' -ErrorAction SilentlyContinue
            $link | Should -Not -BeNullOrEmpty
        }
    }
}
