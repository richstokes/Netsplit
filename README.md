# Overview

During an uncontrolled bout of nostalgia, I thought it might be fun to see what the state of IRC is these days.

I couldn't find a macOS client that I liked, so I built this one.

[<img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83" alt="Download Netsplit on the App Store" height="50">](https://apps.apple.com/us/app/netsplit/id6792029007)

It's 100% free and open source. Contributions welcome, throw me a PR. If changing something graphical, include a screenshot showing what the change is/does.

Open an issue here for bug reports/feature requests.

## SSH tunneling

Each server profile can route its IRC connection through an SSH server. Enable
**Connect through an SSH tunnel** while adding or editing a profile, then enter
the SSH host, port, and username. Password authentication and unencrypted
OpenSSH private keys are supported; secrets are stored in the macOS Keychain.
Ed25519 keys are recommended. RSA keys currently work only with SSH servers
that still permit legacy `ssh-rsa` signatures; many modern servers require
RSA-SHA2, so use Ed25519 or password authentication with those servers.

Netsplit learns the SSH host key on the first connection and pins it to that
server profile. A changed key is rejected until you explicitly forget the saved
host identity. IRC TLS, when enabled, remains end-to-end inside the SSH tunnel.

## On-connect commands

Each server profile can run an ordered list of commands after registration. This
is useful for identifying with NickServ, setting modes, or performing other
network-specific setup. Client commands such as `/msg NickServ IDENTIFY ...`
and raw IRC commands are both accepted. The command list is stored in the macOS
Keychain because it may contain passwords.

Commands are sent 0.5 seconds apart. Netsplit then waits 2 seconds after the
final command before rejoining retained and favorite channels, giving network
services time to apply authentication and account changes.

## Supported commands

Commands are entered in the message field with a leading `/`. Netsplit sends
commands to the server associated with the current conversation, so select a
server, channel, or private message first.

### Messaging

| Command | Description |
| --- | --- |
| `/msg <nickname> <message>` | Send a private message. |
| `/query <nickname> <message>` | Send a private message and open that conversation. |
| `/notice <target> <message>` | Send a notice to a nickname or channel. Incoming notices are displayed too. |
| `/me <action>` | Send a CTCP `ACTION` message to the current channel or private message. |
| `/slap <nickname>` | Send the classic trout-slap action to the current channel or private message. |

### Channels and connections

| Command | Description |
| --- | --- |
| `/join <channel>` | Join a channel. A missing channel prefix is automatically changed to `#`. |
| `/list [arguments]` | Open the live channel browser and request the server's channel list. |
| `/part [#channel] [reason]` | Leave the current channel, a named joined channel, or include a part reason. |
| `/quit [reason]` | Disconnect from the current server. |
| `/topic [#channel] [topic]` | View or change a topic. In a channel, a non-channel first argument is treated as the new topic. |

### Identity and information

| Command | Description |
| --- | --- |
| `/nick <nickname>` | Change your nickname. |
| `/whois <nickname>` | Look up a user's IRC information. |
| `/who <channel-or-nickname>` | Request a WHO listing. |
| `/motd [server]` | Request the server's message of the day. |
| `/version [nickname]` | With no nickname, request the server version; with one, request that user's client version via CTCP. |
| `/ctcp <nickname> version` | Alias for a CTCP client-version request. |

### Modes and moderation

These commands require the appropriate server or channel privileges.

| Command | Description |
| --- | --- |
| `/mode <nickname> <flags>` | View or change user modes. |
| `/mode <#channel> <flags> [arguments]` | View or change channel modes. |
| `/invite <nickname> <#channel>` | Invite a user to a channel. |
| `/kick <#channel> <nickname> [reason]` | Remove a user from a channel. |
| `/kill <nickname> <reason>` | Disconnect a user from the network (IRC operator only). |

### Local controls

| Command | Description |
| --- | --- |
| `/mute <nickname>` | Hide messages and notices from a nickname on the current network. |
| `/unmute <nickname>` | Restore messages and notices from a nickname on the current network. |
| `/showmutes` | List muted nicknames for the current network. |

`/away` and `/names` are also sent directly to the current server. Any other
unrecognised slash command is passed through unchanged, for networks that
support additional IRC commands.
