#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""A small, deterministic IRC server for Netsplit demos and screenshots.

Run it with:

    uv run Scripts/mock_irc_server.py

Then add a Netsplit server profile using 127.0.0.1, port 6667, with TLS,
SASL, and SSH tunneling disabled. The server automatically joins the client
to several channels and fills them with curated members and messages.
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import ipaddress
import signal
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Final

SERVER_NAME: Final = "demo.netsplit.local"
NETWORK_NAME: Final = "NetsplitDemo"
CAPABILITIES: Final = (
    "message-tags",
    "server-time",
    "multi-prefix",
    "userhost-in-names",
    "chghost",
    "echo-message",
)
BASE_TIME: Final = datetime(2026, 7, 23, 16, 0, tzinfo=timezone.utc)
MAX_IRC_LINE_BYTES: Final = 510


@dataclass(frozen=True)
class Member:
    nickname: str
    prefix: str = ""
    username: str | None = None
    hostname: str = "team.demo"

    @property
    def names_token(self) -> str:
        username = self.username or self.nickname.lower()
        return f"{self.prefix}{self.nickname}!{username}@{self.hostname}"


@dataclass(frozen=True)
class Channel:
    name: str
    topic: str
    members: tuple[Member, ...]


@dataclass(frozen=True)
class Event:
    minute: int
    kind: str
    sender: str
    target: str
    text: str = ""
    argument: str = ""


CHANNELS: Final = (
    Channel(
        name="#product",
        topic="A focused launch, thoughtful details, and no surprises",
        members=(
            Member("Alex", "@", hostname="product.demo"),
            Member("Priya", "+", hostname="research.demo"),
            Member("Devon", hostname="engineering.demo"),
            Member("Elena", hostname="design.demo"),
            Member("Hannah", hostname="quality.demo"),
            Member("Jamie", hostname="product.demo"),
            Member("Maya", hostname="design.demo"),
            Member("Noah", hostname="engineering.demo"),
            Member("Omar", hostname="support.demo"),
            Member("Ruby", hostname="writing.demo"),
            Member("Samir", hostname="mobile.demo"),
            Member("Sophie", hostname="community.demo"),
            Member("Theo", hostname="web.demo"),
        ),
    ),
    Channel(
        name="#design",
        topic="Design critique: clear, calm, accessible, and distinctly native",
        members=(
            Member("Maya", "@", hostname="design.demo"),
            Member("Elena", "+", hostname="design.demo"),
            Member("Alex", hostname="product.demo"),
            Member("Hannah", hostname="quality.demo"),
            Member("Iris", hostname="accessibility.demo"),
            Member("Jamie", hostname="product.demo"),
            Member("Leo", hostname="brand.demo"),
            Member("Noah", hostname="engineering.demo"),
            Member("Priya", hostname="research.demo"),
            Member("Ruby", hostname="writing.demo"),
            Member("Samir", hostname="mobile.demo"),
            Member("Theo", hostname="web.demo"),
        ),
    ),
    Channel(
        name="#community",
        topic="Helping people feel welcome — questions and kind feedback encouraged",
        members=(
            Member("Sophie", "@", hostname="community.demo"),
            Member("Omar", "+", hostname="support.demo"),
            Member("Alex", hostname="product.demo"),
            Member("Avery", hostname="community.demo"),
            Member("Casey", hostname="events.demo"),
            Member("Hannah", hostname="quality.demo"),
            Member("Jamie", hostname="product.demo"),
            Member("Jordan", hostname="education.demo"),
            Member("Mina", hostname="localization.demo"),
            Member("Priya", hostname="research.demo"),
            Member("Quinn", hostname="docs.demo"),
            Member("Ruby", hostname="writing.demo"),
        ),
    ),
)


EVENTS: Final = (
    Event(
        0,
        "message",
        "Jamie",
        "#product",
        "Good morning! The release candidate is looking steady. What should we verify first?",
    ),
    Event(
        2,
        "message",
        "Hannah",
        "#product",
        "I finished the clean-install pass on macOS. Setup, reconnect, and notifications all behaved as expected.",
    ),
    Event(
        4,
        "message",
        "Devon",
        "#product",
        "Great. I will take another look at reconnect behavior after sleep and wake.",
    ),
    Event(
        6,
        "message",
        "Priya",
        "#product",
        "The latest usability sessions were encouraging. People found channel switching without prompting.",
    ),
    Event(
        8,
        "action",
        "Noah",
        "#product",
        "updates the launch checklist and pours a second cup of coffee",
    ),
    Event(
        10,
        "message",
        "Ruby",
        "#product",
        "I tightened the release notes. They now lead with the benefit instead of the implementation detail.",
    ),
    Event(
        12,
        "message",
        "Alex",
        "#product",
        "That sounds right. Clear and useful beats clever every time.",
    ),
    Event(
        14,
        "notice",
        "DemoBot",
        "#product",
        "Build 184 passed the smoke-test suite on Apple silicon.",
    ),
    Event(
        16,
        "message",
        "Samir",
        "#product",
        "The memory profile is comfortably inside our target with all demo channels open.",
    ),
    Event(
        18,
        "message",
        "Jamie",
        "#product",
        "{nick}, could you give the final screenshot set a quick look when you have a moment?",
    ),
    Event(
        20,
        "message",
        "Alex",
        "#product",
        "Once that is done, I think we can call this \x02ready for review\x02.",
    ),
    Event(
        1,
        "message",
        "Maya",
        "#design",
        "I posted the refined sidebar treatment. The hierarchy is quieter, but the active channel still reads immediately.",
    ),
    Event(
        3,
        "message",
        "Elena",
        "#design",
        "Nice. The spacing feels especially good in the compact theme.",
    ),
    Event(
        5,
        "message",
        "Iris",
        "#design",
        "VoiceOver order is clean too: server, channel, topic, transcript, then composer.",
    ),
    Event(
        7,
        "message",
        "Leo",
        "#design",
        "The new palette feels confident without competing with conversation content.",
    ),
    Event(
        9,
        "message",
        "Priya",
        "#design",
        "In testing, people consistently described it as “calm” and “easy to scan.”",
    ),
    Event(
        11,
        "message",
        "Maya",
        "#design",
        "Perfect. Those are exactly the words we were designing toward.",
    ),
    Event(
        13,
        "message",
        "Ruby",
        "#design",
        "I also checked the empty states. The language is brief and tells people what to do next.",
    ),
    Event(
        15,
        "join",
        "Fern",
        "#design",
    ),
    Event(
        17,
        "message",
        "Fern",
        "#design",
        "Hello! I reviewed the dark appearance this morning—the contrast and selection states look excellent.",
    ),
    Event(
        19,
        "mode",
        "Maya",
        "#design",
        argument="+v Fern",
    ),
    Event(
        21,
        "topic",
        "Maya",
        "#design",
        "Design critique: clear, calm, accessible, and ready for review",
    ),
    Event(
        1,
        "message",
        "Sophie",
        "#community",
        "Welcome, everyone. Today we are collecting ideas for making first-time IRC users feel at home.",
    ),
    Event(
        3,
        "message",
        "Omar",
        "#community",
        "A short explanation of channels and nicknames would answer most of the questions we see.",
    ),
    Event(
        5,
        "message",
        "Mina",
        "#community",
        "If we keep those strings concise, they will localize cleanly too.",
    ),
    Event(
        7,
        "message",
        "Jordan",
        "#community",
        "Could we include one friendly example conversation? Seeing the rhythm makes the interface click.",
    ),
    Event(
        9,
        "message",
        "Quinn",
        "#community",
        "Absolutely. I can draft something that demonstrates channels without assuming prior IRC knowledge.",
    ),
    Event(
        11,
        "message",
        "Avery",
        "#community",
        "The monthly welcome session is scheduled for Friday. We already have a great group of volunteers.",
    ),
    Event(
        13,
        "message",
        "Casey",
        "#community",
        "Wonderful. I will bring the quick-start cards and make sure there is plenty of time for questions.",
    ),
    Event(
        15,
        "message",
        "Sophie",
        "#community",
        "Thank you all. Patient, human support is still our best feature.",
    ),
    Event(
        22,
        "direct",
        "APartridge",
        "",
        "A-Ha!",
    ),
    Event(
        23,
        "message",
        "Elena",
        "#product",
        "I checked the first-run experience again. The defaults feel sensible without hiding the advanced options.",
    ),
    Event(
        25,
        "message",
        "Theo",
        "#product",
        "The website update is staged too. It matches the app language and keeps the download path obvious.",
    ),
    Event(
        27,
        "message",
        "Hannah",
        "#product",
        "One small issue showed up at the narrowest window size, but I have a clean reproduction.",
    ),
    Event(
        29,
        "message",
        "Devon",
        "#product",
        "Thanks, I found it. A minimum-width calculation was rounding in the wrong direction.",
    ),
    Event(
        31,
        "message",
        "Jamie",
        "#product",
        "Is that safe enough to include today, or should we hold it for the next build?",
    ),
    Event(
        33,
        "message",
        "Devon",
        "#product",
        "It is a two-line fix with a focused regression test. I am comfortable including it.",
    ),
    Event(
        35,
        "action",
        "Samir",
        "#product",
        "starts a fresh performance capture while the new build compiles",
    ),
    Event(
        37,
        "message",
        "Priya",
        "#product",
        "I can run the updated build past two participants this afternoon as an extra confidence check.",
    ),
    Event(
        39,
        "message",
        "Ruby",
        "#product",
        "The help page now covers keyboard navigation and explains the member-role symbols.",
    ),
    Event(
        41,
        "message",
        "DemoBot",
        "#product",
        "Build 185 passed unit, transport, and accessibility smoke tests. https://github.com",
    ),
    Event(
        43,
        "message",
        "Alex",
        "#product",
        "Excellent. Let us keep the rollout gradual and watch feedback closely.",
    ),
    Event(
        45,
        "message",
        "Omar",
        "#product",
        "Support has the new troubleshooting notes. The steps are short and easy to verify.",
    ),
    Event(
        47,
        "message",
        "Jamie",
        "#product",
        "{nick}, the candidate is ready whenever you want to do the final visual pass.",
    ),
    Event(
        49,
        "message",
        "Hannah",
        "#product",
        "The narrow-window regression is fixed. I also checked large text sizes while I was there.",
    ),
    Event(
        51,
        "message",
        "Devon",
        "#product",
        "Sleep, wake, reconnect, and clean quit all passed on the release build.",
    ),
    Event(
        53,
        "message",
        "Alex",
        "#product",
        "That closes the checklist. Thank you, everyone—careful work and a pleasantly uneventful launch.",
    ),
    Event(
        24,
        "message",
        "Maya",
        "#design",
        "I am comparing the light palettes now. The warmer background makes long transcripts feel less stark.",
    ),
    Event(
        26,
        "message",
        "Iris",
        "#design",
        "Agreed. It also preserves enough separation for people using Increase Contrast.",
    ),
    Event(
        28,
        "message",
        "Elena",
        "#design",
        "I adjusted the topic line so it truncates gracefully before competing with the toolbar.",
    ),
    Event(
        30,
        "message",
        "Leo",
        "#design",
        "The icon weight is landing well now—recognizable at a glance without feeling decorative.",
    ),
    Event(
        32,
        "message",
        "Noah",
        "#design",
        "I can make the member-list transition respect Reduce Motion while keeping the layout change clear.",
    ),
    Event(
        34,
        "message",
        "Priya",
        "#design",
        "That would address the only hesitation from yesterday's session.",
    ),
    Event(
        36,
        "message",
        "Ruby",
        "#design",
        "For the connection error, how about “Couldn’t reach the server” followed by the useful detail?",
    ),
    Event(
        38,
        "join",
        "Niko",
        "#design",
    ),
    Event(
        40,
        "message",
        "Niko",
        "#design",
        "Hello! I brought the latest localization screenshots. German and Finnish both fit comfortably.",
    ),
    Event(
        42,
        "mode",
        "Maya",
        "#design",
        argument="+v Niko",
    ),
    Event(
        44,
        "message",
        "Hannah",
        "#design",
        "I tested every appearance at 12, 16, and 24 points. Nothing clips in the main conversation view.",
    ),
    Event(
        46,
        "message",
        "Samir",
        "#design",
        "The colorized nickname option remains easy to distinguish in both dark themes.",
    ),
    Event(
        48,
        "topic",
        "Maya",
        "#design",
        "Final visual review: themes, type, motion, and localization",
    ),
    Event(
        50,
        "message",
        "Iris",
        "#design",
        "The focus ring is visible everywhere now, including the toolbar controls and member search.",
    ),
    Event(
        52,
        "message",
        "Maya",
        "#design",
        "Beautiful. I think the interface is doing its job: supporting the conversation and then getting out of the way.",
    ),
    Event(
        54,
        "action",
        "Elena",
        "#design",
        "pins the approved screenshots and marks the visual review complete",
    ),
    Event(
        23,
        "message",
        "Omar",
        "#community",
        "I reviewed this week's support conversations. Most people were connected and chatting within two minutes.",
    ),
    Event(
        25,
        "message",
        "Mina",
        "#community",
        "The translated quick-start cards are ready in Spanish, French, German, and Japanese.",
    ),
    Event(
        27,
        "message",
        "Sophie",
        "#community",
        "That is fantastic. Let us ask native speakers to give each one a final read before publishing.",
    ),
    Event(
        29,
        "message",
        "Jordan",
        "#community",
        "The beginner workshop outline now includes a five-minute practice chat in small groups.",
    ),
    Event(
        31,
        "message",
        "Quinn",
        "#community",
        "I added a glossary, but kept it optional so newcomers are not greeted with a wall of terminology.",
    ),
    Event(
        33,
        "message",
        "Avery",
        "#community",
        "We have volunteers in six time zones for Friday. Nobody should have to wait long for a friendly hello.",
    ),
    Event(
        35,
        "message",
        "Casey",
        "#community",
        "I will open the room early and test captions before the first session.",
    ),
    Event(
        37,
        "join",
        "Rowan",
        "#community",
    ),
    Event(
        39,
        "message",
        "Rowan",
        "#community",
        "Hi all! I used the new guide today and wanted to say it made my first IRC session surprisingly easy.",
    ),
    Event(
        41,
        "mode",
        "Sophie",
        "#community",
        argument="+v Rowan",
    ),
    Event(
        43,
        "message",
        "Alex",
        "#community",
        "That is wonderful to hear. Was there anything you had to stop and puzzle through?",
    ),
    Event(
        45,
        "message",
        "Rowan",
        "#community",
        "Only the role symbols, and the member-list help explained those right away.",
    ),
    Event(
        47,
        "message",
        "Ruby",
        "#community",
        "Great feedback. I will make that explanation easier to discover from the welcome page too.",
    ),
    Event(
        49,
        "message",
        "Omar",
        "#community",
        "We also refreshed the community guidelines: assume good intent, be specific, and leave room for questions.",
    ),
    Event(
        51,
        "part",
        "Rowan",
        "#community",
        "Thanks for the warm welcome—see you Friday!",
    ),
    Event(
        53,
        "message",
        "Sophie",
        "#community",
        "That interaction is exactly what we want this space to feel like. Nicely done, everyone.",
    ),
    Event(
        54,
        "direct",
        "ClemFandango",
        "",
        "Can you hear me, Steven?",
    ),
)


CHANNEL_BY_NAME: Final = {channel.name.casefold(): channel for channel in CHANNELS}
MEMBER_BY_NICK: Final = {
    member.nickname.casefold(): member
    for channel in CHANNELS
    for member in channel.members
}
MEMBER_BY_NICK["demobot"] = Member("DemoBot", username="bot", hostname=SERVER_NAME)
MEMBER_BY_NICK["fern"] = Member("Fern", username="fern", hostname="design.demo")
MEMBER_BY_NICK["niko"] = Member("Niko", username="niko", hostname="localization.demo")
MEMBER_BY_NICK["rowan"] = Member("Rowan", username="rowan", hostname="people.demo")


def parse_irc_line(line: str) -> tuple[str, list[str], str | None]:
    """Parse the command, middle parameters, and optional trailing parameter."""
    remainder = line.strip("\r\n")
    if remainder.startswith("@"):
        _, separator, remainder = remainder.partition(" ")
        if not separator:
            return "", [], None
    if remainder.startswith(":"):
        _, separator, remainder = remainder.partition(" ")
        if not separator:
            return "", [], None
    middle, separator, trailing = remainder.partition(" :")
    fields = middle.split()
    if not fields:
        return "", [], None
    return fields[0].upper(), fields[1:], trailing if separator else None


def server_time(value: datetime) -> str:
    return value.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def is_loopback_host(host: str) -> bool:
    if host.casefold() == "localhost":
        return True
    with contextlib.suppress(ValueError):
        return ipaddress.ip_address(host).is_loopback
    return False


class DemoSession:
    def __init__(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        *,
        pace: float,
        quiet: bool,
    ) -> None:
        self.reader = reader
        self.writer = writer
        self.pace = pace
        self.quiet = quiet
        self.nickname: str | None = None
        self.username: str | None = None
        self.real_name = "Netsplit Demo User"
        self.cap_negotiating = False
        self.cap_ended = False
        self.registered = False
        self.joined_channels: set[str] = set()
        self.demo_task: asyncio.Task[None] | None = None
        self.write_lock = asyncio.Lock()
        self.close_lock = asyncio.Lock()
        self.is_closed = False

    @property
    def peer_label(self) -> str:
        peer = self.writer.get_extra_info("peername")
        if isinstance(peer, tuple) and len(peer) >= 2:
            return f"{peer[0]}:{peer[1]}"
        return str(peer or "unknown peer")

    @property
    def local_nick(self) -> str:
        return self.nickname or "netsplit"

    @property
    def local_mask(self) -> str:
        username = self.username or "demo"
        return f"{self.local_nick}!{username}@localhost"

    async def run(self) -> None:
        self.log(f"connected: {self.peer_label}")
        try:
            while data := await self.reader.readline():
                if len(data) > MAX_IRC_LINE_BYTES + 2:
                    self.log("closing connection after oversized IRC line")
                    break
                line = data.decode("utf-8", errors="replace").rstrip("\r\n")
                if not line:
                    continue
                self.log(f"<- {line}")
                if not await self.handle_line(line):
                    break
        except (ConnectionError, asyncio.IncompleteReadError):
            pass
        finally:
            await self.close()
            self.log(f"disconnected: {self.peer_label}")

    async def close(self) -> None:
        async with self.close_lock:
            if self.is_closed:
                return
            self.is_closed = True

            if self.demo_task is not None:
                self.demo_task.cancel()
                with contextlib.suppress(asyncio.CancelledError, TimeoutError):
                    await asyncio.wait_for(self.demo_task, timeout=1)
            self.writer.close()
            with contextlib.suppress(ConnectionError, TimeoutError):
                await asyncio.wait_for(self.writer.wait_closed(), timeout=1)

    async def handle_line(self, line: str) -> bool:
        command, parameters, trailing = parse_irc_line(line)

        if command == "CAP":
            await self.handle_cap(parameters, trailing)
        elif command == "PASS":
            pass
        elif command == "NICK":
            new_nick = (parameters[0] if parameters else trailing) or ""
            if not new_nick:
                await self.numeric("431", trailing="No nickname given")
            elif self.registered:
                old_mask = self.local_mask
                self.nickname = new_nick
                await self.send(f":{old_mask} NICK :{new_nick}")
            else:
                self.nickname = new_nick
                await self.maybe_register()
        elif command == "USER":
            if parameters:
                self.username = parameters[0]
            if trailing:
                self.real_name = trailing
            await self.maybe_register()
        elif command == "PING":
            token = trailing or (parameters[0] if parameters else SERVER_NAME)
            await self.send(f":{SERVER_NAME} PONG {SERVER_NAME} :{token}")
        elif command == "PONG":
            pass
        elif command == "JOIN":
            raw_channels = parameters[0] if parameters else trailing or ""
            for raw_channel in raw_channels.split(","):
                channel_name = self.normalized_channel(raw_channel)
                if channel_name:
                    await self.join_channel(channel_name, acknowledge_repeat=True)
        elif command == "PART":
            if parameters:
                channel_name = self.normalized_channel(parameters[0])
                if channel_name:
                    reason = trailing or "Leaving"
                    await self.send(f":{self.local_mask} PART {channel_name} :{reason}")
                    self.joined_channels.discard(channel_name.casefold())
        elif command == "PRIVMSG":
            if parameters and trailing is not None:
                target = parameters[0]
                await self.send_tagged(
                    datetime.now(timezone.utc),
                    f":{self.local_mask} PRIVMSG {target} :{trailing}",
                )
        elif command == "NOTICE":
            pass
        elif command == "TOPIC":
            await self.handle_topic(parameters, trailing)
        elif command == "MODE":
            await self.handle_mode(parameters)
        elif command == "LIST":
            await self.send_channel_list()
        elif command == "WHOIS":
            await self.send_whois(parameters)
        elif command == "WHO":
            await self.send_who(parameters)
        elif command == "MOTD":
            await self.send_motd()
        elif command == "VERSION":
            await self.numeric(
                "351",
                "mock-irc-1.0",
                SERVER_NAME,
                trailing="Netsplit screenshot server",
            )
        elif command == "AWAY":
            if trailing:
                await self.numeric("306", trailing="You have been marked as away")
            else:
                await self.numeric("305", trailing="You are no longer marked as away")
        elif command == "INVITE":
            if len(parameters) >= 2:
                await self.numeric(
                    "341",
                    parameters[0],
                    parameters[1],
                    trailing="Inviting user",
                )
        elif command == "KICK":
            if len(parameters) >= 2:
                reason = trailing or self.local_nick
                await self.send(
                    f":{self.local_mask} KICK {parameters[0]} {parameters[1]} :{reason}"
                )
        elif command == "QUIT":
            await self.send(
                f":{SERVER_NAME} ERROR :Closing Link: {self.local_nick} (Client quit)"
            )
            return False
        elif command:
            await self.numeric("421", command, trailing="Unknown command")

        return True

    async def handle_cap(self, parameters: list[str], trailing: str | None) -> None:
        if not parameters:
            return
        subcommand = parameters[0].upper()
        if subcommand == "LS":
            self.cap_negotiating = True
            await self.send(f":{SERVER_NAME} CAP * LS :{' '.join(CAPABILITIES)}")
        elif subcommand == "REQ":
            requested = trailing or " ".join(parameters[1:])
            requested_names = {
                token.lstrip("-").split("=", maxsplit=1)[0]
                for token in requested.split()
            }
            available = set(CAPABILITIES)
            if requested_names <= available:
                await self.send(f":{SERVER_NAME} CAP * ACK :{requested}")
            else:
                await self.send(f":{SERVER_NAME} CAP * NAK :{requested}")
        elif subcommand == "END":
            self.cap_ended = True
            await self.maybe_register()

    async def maybe_register(self) -> None:
        if (
            self.registered
            or not self.nickname
            or not self.username
            or (self.cap_negotiating and not self.cap_ended)
        ):
            return

        self.registered = True
        await self.numeric(
            "001",
            trailing=f"Welcome to the Netsplit demo network, {self.local_nick}",
        )
        await self.numeric(
            "002",
            trailing=f"Your host is {SERVER_NAME}, running mock-irc-1.0",
        )
        await self.numeric(
            "003",
            trailing="This server was created for calm, deterministic screenshots",
        )
        await self.send(
            f":{SERVER_NAME} 004 {self.local_nick} {SERVER_NAME} "
            "mock-irc-1.0 io mtov"
        )
        await self.send(
            f":{SERVER_NAME} 005 {self.local_nick} "
            "CHANTYPES=# PREFIX=(qaohv)~&@%+ CASEMAPPING=rfc1459 "
            f"NETWORK={NETWORK_NAME} STATUSMSG=@+ NICKLEN=30 "
            "CHANNELLEN=50 MODES=4 "
            ":are supported by this server"
        )
        await self.send_motd()
        self.demo_task = asyncio.create_task(self.play_demo())

    async def play_demo(self) -> None:
        # Netsplit rejoins retained and favorite channels shortly after
        # registration. Give those client-driven JOINs priority so the automatic
        # demo joins do not race them and create duplicate join events.
        await asyncio.sleep(1.5)
        for channel in CHANNELS:
            await self.join_channel(channel.name)
            await self.pause()

        for event in sorted(EVENTS, key=lambda item: item.minute):
            await self.send_event(event)
            await self.pause()

        self.log("demo transcript complete; the server remains interactive")

    async def join_channel(
        self, channel_name: str, *, acknowledge_repeat: bool = False
    ) -> None:
        channel_key = channel_name.casefold()
        is_repeat = channel_key in self.joined_channels
        if is_repeat and not acknowledge_repeat:
            return

        if not is_repeat:
            self.joined_channels.add(channel_key)
        channel = CHANNEL_BY_NAME.get(channel_key)
        if channel is None:
            channel = Channel(
                name=channel_name,
                topic="A friendly place for thoughtful conversation",
                members=(
                    Member("Alex", "@", hostname="product.demo"),
                    Member("Maya", "+", hostname="design.demo"),
                    Member("Sophie", hostname="community.demo"),
                ),
            )

        await self.send_tagged(
            BASE_TIME - timedelta(minutes=3),
            f":{self.local_mask} JOIN {channel.name}",
        )
        await self.numeric("332", channel.name, trailing=channel.topic)
        await self.numeric(
            "333",
            channel.name,
            "Maya",
            str(int(BASE_TIME.timestamp())),
        )

        local_member = Member(
            self.local_nick,
            username=self.username or "demo",
            hostname="localhost",
        )
        tokens = [local_member.names_token]
        tokens.extend(member.names_token for member in channel.members)
        for names_chunk in self.chunk_names(tokens):
            await self.send(
                f":{SERVER_NAME} 353 {self.local_nick} = "
                f"{channel.name} :{' '.join(names_chunk)}"
            )
        await self.numeric("366", channel.name, trailing="End of /NAMES list")

    async def send_event(self, event: Event) -> None:
        timestamp = BASE_TIME + timedelta(minutes=event.minute)
        text = event.text.replace("{nick}", self.local_nick)
        mask = self.nickmask(event.sender)

        if event.kind == "message":
            await self.send_tagged(
                timestamp,
                f":{mask} PRIVMSG {event.target} :{text}",
            )
        elif event.kind == "notice":
            await self.send_tagged(
                timestamp,
                f":{mask} NOTICE {event.target} :{text}",
            )
        elif event.kind == "action":
            await self.send_tagged(
                timestamp,
                f":{mask} PRIVMSG {event.target} " f":\x01ACTION {text}\x01",
            )
        elif event.kind == "direct":
            await self.send_tagged(
                timestamp,
                f":{mask} PRIVMSG {self.local_nick} :{text}",
            )
        elif event.kind == "join":
            await self.send_tagged(
                timestamp,
                f":{mask} JOIN {event.target}",
            )
        elif event.kind == "part":
            await self.send_tagged(
                timestamp,
                f":{mask} PART {event.target} :{text or 'See you soon'}",
            )
        elif event.kind == "mode":
            await self.send_tagged(
                timestamp,
                f":{mask} MODE {event.target} {event.argument}",
            )
        elif event.kind == "topic":
            await self.send_tagged(
                timestamp,
                f":{mask} TOPIC {event.target} :{text}",
            )

    async def handle_topic(self, parameters: list[str], trailing: str | None) -> None:
        if not parameters:
            await self.numeric("461", "TOPIC", trailing="Not enough parameters")
            return
        channel_name = self.normalized_channel(parameters[0])
        if not channel_name:
            return
        if trailing is not None:
            await self.send(f":{self.local_mask} TOPIC {channel_name} :{trailing}")
            return
        channel = CHANNEL_BY_NAME.get(channel_name.casefold())
        topic = (
            channel.topic if channel else "A friendly place for thoughtful conversation"
        )
        await self.numeric("332", channel_name, trailing=topic)

    async def handle_mode(self, parameters: list[str]) -> None:
        if not parameters:
            await self.numeric("461", "MODE", trailing="Not enough parameters")
            return
        target = parameters[0]
        if len(parameters) == 1:
            if target.startswith("#"):
                await self.numeric("324", target, "+nt")
            else:
                await self.numeric("221", "+i")
            return
        if target.startswith("#") and parameters[1] == "+b":
            await self.numeric("368", target, trailing="End of channel ban list")
            return
        await self.send(f":{self.local_mask} MODE {' '.join(parameters)}")

    async def send_channel_list(self) -> None:
        await self.numeric("321", "Channel", "Users", trailing="Name")
        for channel in CHANNELS:
            await self.numeric(
                "322",
                channel.name,
                str(len(channel.members) + 1),
                trailing=channel.topic,
            )
        await self.numeric("323", trailing="End of /LIST")

    async def send_whois(self, parameters: list[str]) -> None:
        target = parameters[-1] if parameters else self.local_nick
        member = MEMBER_BY_NICK.get(target.casefold())
        username = member.username if member and member.username else target.lower()
        hostname = member.hostname if member else "people.demo"
        await self.numeric(
            "311",
            target,
            username,
            hostname,
            "*",
            trailing=f"{target} — Netsplit Demo Network",
        )
        await self.numeric("312", target, SERVER_NAME, trailing="Netsplit Demo Network")
        await self.numeric("318", target, trailing="End of /WHOIS list")

    async def send_who(self, parameters: list[str]) -> None:
        target = parameters[0] if parameters else "#product"
        channel = CHANNEL_BY_NAME.get(target.casefold())
        members = channel.members if channel else ()
        for member in members:
            username = member.username or member.nickname.lower()
            await self.send(
                f":{SERVER_NAME} 352 {self.local_nick} {target} "
                f"{username} {member.hostname} {SERVER_NAME} "
                f"{member.nickname} H :0 {member.nickname}"
            )
        await self.numeric("315", target, trailing="End of /WHO list")

    async def send_motd(self) -> None:
        await self.numeric("375", trailing=f"- {SERVER_NAME} Message of the Day -")
        await self.numeric(
            "372",
            trailing="- Welcome to a local, deterministic network made for demos.",
        )
        await self.numeric(
            "372",
            trailing="- Everything here is fictional, friendly, and safe to screenshot.",
        )
        await self.numeric("376", trailing="End of /MOTD command")

    async def numeric(
        self, code: str, *parameters: str, trailing: str | None = None
    ) -> None:
        middle = " ".join((self.local_nick, *parameters))
        suffix = f" :{trailing}" if trailing is not None else ""
        await self.send(f":{SERVER_NAME} {code} {middle}{suffix}")

    async def send_tagged(self, timestamp: datetime, line: str) -> None:
        await self.send(f"@time={server_time(timestamp)} {line}")

    async def send(self, line: str) -> None:
        clean_line = line.replace("\r", "").replace("\n", "")
        encoded = clean_line.encode("utf-8")
        if len(encoded) > MAX_IRC_LINE_BYTES:
            raise ValueError(
                f"IRC line exceeds {MAX_IRC_LINE_BYTES} bytes: {clean_line}"
            )
        if self.writer.is_closing():
            return
        async with self.write_lock:
            self.log(f"-> {clean_line}")
            self.writer.write(encoded + b"\r\n")
            await self.writer.drain()

    async def pause(self) -> None:
        if self.pace > 0:
            await asyncio.sleep(self.pace)

    def nickmask(self, nickname: str) -> str:
        member = MEMBER_BY_NICK.get(nickname.casefold())
        username = member.username if member and member.username else nickname.lower()
        hostname = member.hostname if member else "people.demo"
        return f"{nickname}!{username}@{hostname}"

    @staticmethod
    def normalized_channel(raw_channel: str) -> str:
        channel = raw_channel.strip()
        if not channel:
            return ""
        return channel if channel.startswith("#") else f"#{channel}"

    @staticmethod
    def chunk_names(tokens: list[str]) -> list[list[str]]:
        chunks: list[list[str]] = []
        current: list[str] = []
        current_length = 0
        for token in tokens:
            token_length = len(token.encode("utf-8")) + (1 if current else 0)
            if current and current_length + token_length > 300:
                chunks.append(current)
                current = []
                current_length = 0
            current.append(token)
            current_length += token_length
        if current:
            chunks.append(current)
        return chunks

    def log(self, message: str) -> None:
        if not self.quiet:
            print(f"[{self.peer_label}] {message}", flush=True)


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Run a local scripted IRC server for Netsplit demos and screenshots."
        ),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Address to bind. Loopback is strongly recommended.",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=6667,
        help="Plaintext IRC port.",
    )
    parser.add_argument(
        "--pace",
        type=float,
        default=0.10,
        help="Seconds between scripted joins and messages; use 0 for instant population.",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress per-connection IRC traffic logs.",
    )
    return parser


async def run_server(arguments: argparse.Namespace) -> int:
    if not 1 <= arguments.port <= 65535:
        raise SystemExit("--port must be between 1 and 65535")
    if arguments.pace < 0:
        raise SystemExit("--pace cannot be negative")

    if not is_loopback_host(arguments.host):
        print(
            "warning: this demo server has no authentication and is intended "
            "for loopback use only",
            flush=True,
        )

    sessions: set[DemoSession] = set()
    connection_tasks: set[asyncio.Task[None]] = set()

    async def accept(
        reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        session = DemoSession(
            reader,
            writer,
            pace=arguments.pace,
            quiet=arguments.quiet,
        )
        task = asyncio.current_task()
        sessions.add(session)
        if task is not None:
            connection_tasks.add(task)
        try:
            await session.run()
        finally:
            sessions.discard(session)
            if task is not None:
                connection_tasks.discard(task)

    try:
        server = await asyncio.start_server(
            accept,
            host=arguments.host,
            port=arguments.port,
            limit=MAX_IRC_LINE_BYTES + 2,
        )
    except OSError as error:
        print(
            f"error: could not listen on {arguments.host}:{arguments.port}: {error}",
            flush=True,
        )
        return 1

    addresses = ", ".join(str(socket.getsockname()) for socket in server.sockets or ())
    print("Netsplit mock IRC server is ready.", flush=True)
    print(f"Listening on {addresses}", flush=True)
    print(
        "Connect with hostname "
        f"{arguments.host}, port {arguments.port}, TLS off, SASL off, SSH off.",
        flush=True,
    )
    print("Press Control-C to stop.", flush=True)

    stop_event = asyncio.Event()

    def request_stop() -> None:
        if not stop_event.is_set():
            print("\nStopping mock IRC server…", flush=True)
            stop_event.set()

    loop = asyncio.get_running_loop()
    for signal_name in (signal.SIGINT, signal.SIGTERM):
        with contextlib.suppress(NotImplementedError):
            loop.add_signal_handler(signal_name, request_stop)

    await stop_event.wait()
    server.close()

    if sessions:
        await asyncio.gather(
            *(session.close() for session in tuple(sessions)),
            return_exceptions=True,
        )

    if connection_tasks:
        _, pending_tasks = await asyncio.wait(
            tuple(connection_tasks),
            timeout=2,
        )
        for task in pending_tasks:
            task.cancel()
        if pending_tasks:
            await asyncio.gather(*pending_tasks, return_exceptions=True)

    await server.wait_closed()
    print("Mock IRC server stopped.", flush=True)
    return 0


def main() -> int:
    arguments = build_argument_parser().parse_args()
    try:
        return asyncio.run(run_server(arguments))
    except KeyboardInterrupt:
        print("\nMock IRC server stopped.", flush=True)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
