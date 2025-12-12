# Technical Notes Transcript (Cleaned)

Voice memo recorded December 9, 2025, ruminating on interesting technical details from Contextify development for potential Show HN talking points.

---

## Transcript Parsing: Claude Code vs Codex

I got to know transcripts from Claude Code and OpenAI Codex quite well because you have to parse them to create a database. There are a lot of similarities between the two formats, but there's an incredible amount of nuance.

### Transcript Corruption

One example is corruption. There was a great deal of corruption in Claude Code transcripts during the Claude Code free API credits giveaway a few weeks ago. If you ever used the "resume this conversation in the CLI" button and saw a 400 error when you tried to chat, it was due to a bug.

I was working so closely with this that I was able to write a script to repair the corruption. When I asked about people struggling with this, there weren't enough people experiencing it to get traction. But if you look in the Claude Code release notes following that, towards the tail end of the API credit expiration, they had something about how they made transcript parsing "robust." I'm guessing Anthropic wrote their own repair tool.

### Session Management & Sync

Anthropic's done some interesting things around session management, which I believe they think of as a higher level than transcripts. When you're in the CLI and then go back to Claude Code Web, the additional discussion you had in the CLI is supposed to be reflected there. However, this conversation is now stored on your local box, so there's a sync question. It's worth additional exploration.

---

## Claude Code's Queue System

A really interesting thing about Claude Code transcripts: Cloud Code's transcripts are much more sophisticated at this point than Codex. They do a thing with queuing that is subtle.

If you've used both Codex and Claude Code a lot, you can tell that if you send a message to Claude Code while it's already working on something, it is really good at pulling your message into its ongoing effort. Sometimes it will acknowledge what you said and say it will handle that after it finishes the more important task that it's halfway through. Sometimes it will ignore it, but after completing the other task, it will actually follow up like it was planning to the entire time, it just didn't say it.

This behavior where it seems to know it has something to do, can even switch directions, is pretty incredible. It uses a queuing mechanism with a "queued" key.

**[Editor's note: Look at actual transcript format docs and code for technical details on the queue-operation records.]**

Codex does not offer that queuing at all.

The cool thing for Contextify was that I was able to actually display messages that are queued and then clean that up. You see a cool tag that says "queued" in the conversation log, and then it changes, that tag goes away.

---

## Git Branch Display

Another cool thing about Claude Code is that it includes your Git branch that you're working on all the time. The messages contain your Git branch. Codex does not.

On the App Store, there's a lot of sandboxing. I didn't get it in the first version, but I'll be able to display your current Git branch on the DMG version. But on App Store, I can't do that without getting permissions to your actual home project directory on an individual case-by-case basis. That's a lot of permissions to ask for.

But on Claude Code, I don't need filesystem permissions. I can still provide the same feature set because it's in the transcript. Codex, I can't, I'd have to infer it from the messages, but not really.

---

## LLM Summarization Challenges

There's some really cool things around summarization. I learned a lot about LLM summarization, the idea of grounding, because I'm constantly trying to have the LLM confirm what, or summarize what, you and the AI are saying and the intent of these things. Otherwise the summarization will come across incorrectly.

There are many, many ways to go wrong here. I've got a list of ones I don't handle properly right now. I even have a slash command for quickly adding a summarization failure so I can batch these and fix them together.

But I do handle a lot of them, including expletives. Apple Intelligence, Apple's foundation LLM, won't summarize messages that contain expletives. So I have to add handling for the error that would pop up on that and do something called tombstoning.

**[Editor's note: Document tombstoning implementation, how we handle permanent summarization failures.]**

---

## Scaling to Thousands of Transcripts

There's some interesting things around scaling. I've got many, many Claude Code sessions and some Codex sessions, but not nearly as many as Claude Code.

There's a lot to how I built Contextify for quick display of conversation information upon ingestion. If you've used Claude Code as much as me, you've got over a thousand transcripts locally. This is presuming many of them have been deleted already by the auto-delete.

**[Editor's note: We should add to our help pages a recommendation that people turn off the auto-delete and explain how to do that.]**

When you're ingesting thousands of transcripts, you can't just do it all the time. It will lock up the app. I mean you can, but it's not a great first experience. So I put a lot of time into adding lazy loading of ingestion of these text files and preventing it from hogging the UI.

---

## macOS Tahoe

Another item is it's macOS Tahoe only. This is probably controversial. I know not everybody has great feelings about Apple's design choices on Tahoe. It's a trope at this point to discuss Apple's ecosystem and what that can mean as far as lock-in and whether they're properly servicing their tools with bug fixes, etc.

But you should put all that aside if you've leaned into Tahoe. I guess this is a minor item, but I did try using Liquid Glass and it wasn't that great. I don't think that was worth pursuing.

---

## Positioning: Above the Status Bar

I wanted to make sure I wasn't taking the approach of showing things that you could already display in the status bar. It's important that this be trying to act at the level above the two different providers.

Right now it's largely a read-only tool. You can view your messages, you can search through them. But I see opportunity for this at sort of an orchestrator level, or at least acting as a potential peer to Claude Code and Codex. I don't have a lot more to say about that yet, but I do think there's some really cool things that can be done here.

---

## Future: Gemini and Other CLIs

On transcripts, just pointing at Gemini: Gemini doesn't yet support local transcript storage, which is kind of a thing. There's some open issues where they're trying to get local transcript storage in, but have not.

**[Editor's note: Verify the Gemini issue status.]**

I'm expecting to support Gemini once it's available, and really any other CLI AIs that generate transcripts that people want or that I would use.

---

## Community & Feedback

It might be worth mentioning that we're using GitHub issues in a public repo where the DMG releases are going to be posted for bug reports and feature requests, just like Anthropic is doing. Encourage people to go there if they're liking the app and want to provide feedback. Happy to acknowledge requests and try to get them in.

---

## App Store & Enterprise IT

It might be worth mentioning specifically about the App Store and enterprise or corporate IT policy. It's a huge pain in the ass to support the App Store, really, for this kind of thing. But I'm trying to go the extra mile to do that so that people can get access to the tool.

---

## Development Story: Python Dev Building a macOS App

It might be worth discussing how I built this app. I'm a Python developer, and I've worked on projects in Xcode with a lot of releases for iOS. But this is my first macOS release and my deepest incursion into the Swift and SwiftUI ecosystem.

### Building Without Xcode Open

It should be worth noting that I did most of this project without the use of Xcode. My build process runs without Xcode open. I only really use Xcode for instrumentation, trying to deal with some performance issues and trying to understand how to do profiling correctly, especially for that initial load with thousands of transcripts.

It's probably controversial to some extent that I'm not keeping Xcode open and watching line-by-line changes. But I've also come up with a number of novel developer environment setups that have allowed me to get the project to this level of maturity.

### The rm -rf Incident

Another noteworthy thing is that a lot of this project I ran dangerously skipping permissions. At one point, about a third of the way through development, I had instructed Claude Code to remove an extraneous duplicative build directory, a `.derived` directory.

Claude Code made a mistake that deleted my user directory on macOS with an `rm -rf`. It effectively broke my computer.

The funny thing is there's a post on Reddit from the last two days where somebody describes a similar thing, and I didn't even bother commenting. I didn't comment on it when it happened because somebody had mentioned it before. I'm a little surprised it's still happening because I think Anthropic has made attempts to reduce the likelihood of this occurring, they did add the sandbox, which I've tried but I was not entirely satisfied with.

**The bad news:** I lost about a day and a half of work and some small projects that I did not keep in source control.

**The upside:** My aging MacBook Air M2, it's a tricked out M2, fully loaded with two terabytes, I had a lot of space after I did a complete fresh install. The computer's operating a lot faster. If it's been a couple of years since you did a full wipe, I used to do this in Windows, it was a common thing, you had to reinstall, but it actually still has a big impact on macOS after a few years.

The other thing is I got a real backup in place beyond my own source control and was more cognizant of that. Fortunately I keep a lot in safe places in the cloud.

I recognize that not everybody can run their CLI AIs dangerously skipping permissions, and I know the possible potential result of that. But even after that occurred, I still do it. It doesn't bother me. Knock on wood.

---

*End of transcript (combined from three recordings)*
