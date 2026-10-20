# Update and roll back

uupd (from upstream) updates automatically: on a schedule, and on a laptop once
it's on AC power. The new image is staged and takes effect at the next boot.

```bash
sudo bootc status                # booted, staged and rollback deployments
sudo bootc upgrade --check       # is there a newer digest?
sudo bootc upgrade               # stage it now instead of waiting for uupd
sudo systemctl reboot
```

## Roll back

Choose the previous entry in the GRUB menu, or from a running system:

```bash
sudo bootc rollback && sudo systemctl reboot
```

The journal is volatile, so the failed boot's logs are gone. Reproduce the
failure in a VM (`just build-qcow2 && just run-vm-qcow2`) rather than on the
laptop.

## Channels

| Tag | Built from | Use |
| --- | --- | --- |
| `:stable` | the **Release** workflow, promoting a signed `:stable-testing` digest | the laptop |
| `:stable-testing` | every push to `main`, and daily | trying a change first |
| `:<version>` | one per release, never moves | pinning a machine |

```bash
sudo bootc switch ghcr.io/cpmorton/daily-driver-os:stable-testing   # and back to :stable
```
