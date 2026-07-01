location       = "Central US"
rdp_source     = "99.7.232.176/32" # Find at whatismyip.com — format: 1.2.3.4/32
server_vm_size = "Standard_D2s_v3"
client_vm_size = "Standard_D2s_v3"

# admin_password is NOT set here — use an environment variable:
#   PowerShell: $env:TF_VAR_admin_password = "YourStrongPassword!"
#   Bash:       export TF_VAR_admin_password="YourStrongPassword!"
# Min 12 chars, upper + lower + number + symbol.
