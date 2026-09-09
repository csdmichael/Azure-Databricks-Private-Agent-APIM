using './main.bicep'

// Matches the canada geo of Power Platform environment 52456fcd-1d20-ecdb-aa2e-8979e3f794f5.
param primaryRegion = 'canadacentral'
param secondaryRegion = 'canadaeast'
param primaryVnetCidr = '10.194.0.0/16'
param primarySubnetCidr = '10.194.0.0/24'
param secondaryVnetCidr = '10.195.0.0/16'
param secondarySubnetCidr = '10.195.0.0/24'
param policyLocation = 'canada'
param enterprisePolicyName = 'caldova-pp-network-injection-canada'
