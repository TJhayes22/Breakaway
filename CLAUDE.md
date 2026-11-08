# CLAUDE.md — Roblox Hockey Game

## 1. Project Overview

We are developing a multiplayer, physics-based hockey game in Roblox Studio, heavily inspired by the gameplay experience of **Puck**.

The goal is to recreate the satisfying physics, skill-based mechanics, and immersive hockey experience of Puck while building an original Roblox game with its own identity, progression, customization, and community.

This is a blank project. We are starting from scratch.

### Core Game Vision

- Physics-driven hockey gameplay.
- Strictly first-person during actual hockey gameplay.
- Third-person camera in the lobby and customization areas.
- Independently controlled hockey stick.
- Physically simulated puck with realistic momentum and collisions.
- Fast-paced 3v3 multiplayer matches.
- AI-controlled goalies.
- Persistent social lobby.
- Cosmetic customization and player progression.
- Accessible arcade-style experience with a meaningful skill ceiling.

The most important priority is making hockey feel GOOD to play.

Do not sacrifice the quality of puck physics, skating, stick control, or shooting to rush other features.

---

## 2. Research Puck Before Development

Before implementing gameplay mechanics, research the existing game **Puck**.

I want you to understand what makes its gameplay satisfying and identify which mechanics we should recreate or adapt for Roblox.

Research publicly available gameplay footage, videos, screenshots, community discussions, and other legitimate sources.

Pay particular attention to:

1. First-person camera behavior.
2. Player skating and movement physics.
3. Acceleration, momentum, friction, and turning.
4. Independent hockey stick control.
5. Stick positioning and blade interaction.
6. Puck movement and physical interactions.
7. Shooting mechanics and shot power.
8. Passing and stickhandling.
9. Player-to-player collisions and checking.
10. Overall match pacing and gameplay flow.

### Research Expectations

- Do not assume how Puck works. Research and observe it.
- Distinguish between confirmed observations and your own interpretations.
- Identify the mechanics that contribute most to the gameplay experience.
- Look for community feedback about what players enjoy and dislike.
- Identify which mechanics are feasible to recreate using Roblox physics.
- Consider Roblox networking, latency, and multiplayer synchronization limitations.

Do not copy proprietary code, assets, branding, or protected content.

The goal is to take inspiration from the gameplay experience and create an original implementation.

### Research Deliverable

Create a document named `docs/PUCK_GAMEPLAY_RESEARCH.md`.

Include:
- Observed gameplay mechanics.
- Important physics behaviors.
- Camera and control observations.
- Potential Roblox implementation approaches.
- Technical challenges.
- Recommended initial prototype specifications.
- Sources and links.

Do not start implementing the entire game immediately after research. First present your findings and recommended development plan.

---

## 3. Core Gameplay Design

### Match Format

Our initial target game mode is:

- 3 players versus 3 players.
- AI-controlled goalies on both teams.
- Short, fast-paced matches.
- Approximately 3–4 minutes per match as an initial design target.
- Quick faceoffs and minimal downtime.
- Simple arcade-style rules.
- Focus on puck possession, shooting, passing, and teamwork.

Avoid unnecessary simulation systems such as complicated penalties, icing, and offsides in the initial version.

### Camera System

There are two distinct camera environments.

**Lobby:**
- Third-person camera.
- Players can see their characters and other players.
- Players can display their cosmetic equipment.
- Locker room and customization interfaces.

**Gameplay:**
- Strictly first-person.
- No third-person switching.
- Visible player arms, gloves, and hockey stick.
- Smooth camera movement.
- Subtle skating movement and camera feedback.
- Puck should remain easy to track.

### Skating Physics

We want momentum-based movement rather than standard Roblox character movement.

Consider:
- Acceleration.
- Deceleration.
- Momentum preservation.
- Friction.
- Turning resistance.
- Sprinting.
- Collisions.
- Responsive but believable skating.

The player should feel like they are skating on ice rather than walking on a normal Roblox map.

### Hockey Stick Mechanics

The hockey stick is one of the most important systems.

We want independent stick control inspired by Puck.

Investigate approaches for:
- Stick positioning relative to the player.
- Blade positioning and orientation.
- Stick movement and rotation.
- Physical puck interaction.
- Shooting.
- Passing.
- Stickhandling.
- Defensive stick interactions.

Do not implement shooting as a simple button that automatically launches the puck toward a target.

The stick and puck should interact in a way that rewards player positioning, timing, and control.

### Puck Physics

The puck must feel satisfying and believable.

Consider:
- Linear momentum.
- Angular velocity and spin.
- Ice friction.
- Board collisions.
- Player collisions.
- Stick collisions.
- Rebounds.
- Shooting velocity.
- Passing velocity.
- Network synchronization.

Investigate whether Roblox assemblies, constraints, custom force controllers, or another approach would provide the best result.

Avoid unnecessarily complicated physics if a simpler solution achieves the desired gameplay.

---

## 4. Lobby and Game Structure

The game will have a persistent social lobby.

### Lobby Features

Eventually, the lobby should include:

- Third-person player movement.
- A central social area.
- Practice rink.
- Matchmaking area.
- Locker room.
- Cosmetic shop.
- Leaderboards.
- Player statistics.
- Customization interfaces.

Players should be able to practice shooting and stickhandling while waiting for matches.

### Matchmaking

Players should be able to queue for 3v3 matches.

The intended flow:

1. Player joins the lobby.
2. Player customizes their character or practices.
3. Player joins matchmaking.
4. Six players are assigned to a match.
5. Players enter a dedicated match environment.
6. Match concludes.
7. Players receive XP and currency.
8. Players return to the lobby.

Research appropriate Roblox services, including TeleportService and reserved servers, before choosing the final architecture.

Do not prematurely commit to a server structure without evaluating its tradeoffs.

---

## 5. Progression and Customization

Customization is an important part of long-term player retention.

Potential cosmetic categories:

- Hockey sticks.
- Stick tape.
- Jerseys.
- Gloves.
- Skates.
- Helmets.
- Goalie masks.
- Goal celebrations.
- Puck trails.
- Other visual effects.

### Progression

Players should earn rewards through playing.

Potential systems:
- Match XP.
- Player levels.
- In-game currency.
- Daily challenges.
- Weekly challenges.
- Achievements.
- Seasonal rewards.
- Cosmetic collections.

### Monetization

Potential monetization:
- Direct cosmetic purchases using Robux.
- Cosmetic bundles.
- Earnable reward crates.
- Seasonal cosmetic collections.

Gameplay must remain fair.

Cosmetics must NEVER provide competitive advantages such as additional shooting power, skating speed, or accuracy.

Research current Roblox policies before implementing paid random-item mechanics. Include applicable odds disclosures, PolicyService restrictions, and other relevant requirements.

Do not prioritize monetization before the core gameplay is enjoyable.

---

## 6. Technical Development Guidelines

We are using:
- Roblox Studio.
- Luau.
- Claude Code.
- Roblox Studio MCP server.

You should use the available Roblox Studio MCP tools to inspect and interact with the actual project.

### General Rules

1. Inspect the existing project before making changes.
2. Understand the existing hierarchy and scripts.
3. Keep scripts organized and modular.
4. Avoid putting the entire game into one large script.
5. Use clear naming conventions.
6. Add comments where useful.
7. Avoid unnecessary abstractions.
8. Do not introduce external dependencies without justification.
9. Consider server performance and multiplayer replication.
10. Never assume a feature works without testing it.

### Networking and Security

The server should be authoritative over important competitive game state.

Pay particular attention to:
- Puck ownership and synchronization.
- Player movement validation.
- Shot validation.
- Goal detection.
- Match state.
- Player rewards.
- Exploit prevention.

Evaluate Roblox network ownership carefully. Do not allow clients to freely manipulate competitive puck physics without server validation.

Aim for responsive gameplay without compromising competitive integrity.

### Architecture

Use modular systems where appropriate.

Potential organization:

- `ReplicatedStorage`
  - Shared modules.
  - RemoteEvents.
  - Configuration.
  - Shared types.

- `ServerScriptService`
  - Game systems.
  - Puck physics.
  - Match management.
  - Player data.
  - AI goalies.

- `StarterPlayer`
  - Client controllers.
  - Camera.
  - Input.
  - Hockey stick visuals.
  - UI controllers.

- `StarterGui`
  - Gameplay HUD.
  - Lobby UI.
  - Customization UI.

- `Workspace`
  - Lobby.
  - Rink.
  - Puck.
  - Gameplay objects.

Adapt this organization as the project grows. Do not create empty folders and unnecessary systems just to match this example.

---

## 7. Development Roadmap

Development should happen incrementally.

Do not attempt to build the entire game in one step.

### Phase 1: Research and Planning
- Research Puck gameplay.
- Investigate Roblox physics capabilities.
- Evaluate possible movement and stick-control approaches.
- Create a technical architecture proposal.

### Phase 2: First Physics Prototype
- Create an empty hockey rink.
- Implement a first-person camera.
- Implement basic skating.
- Create a physical puck.
- Implement puck friction and collisions.
- Test movement and puck interaction.

### Phase 3: Hockey Stick
- Implement visible hockey stick.
- Add independent stick positioning.
- Add blade-puck interaction.
- Implement shooting.
- Implement passing.
- Improve stickhandling.

### Phase 4: Multiplayer
- Synchronize player movement.
- Synchronize puck physics.
- Test multiple players interacting with the puck.
- Address latency and network ownership.
- Test competitive fairness.

### Phase 5: Complete Hockey Gameplay
- Add player collisions.
- Add checking.
- Implement AI goalies.
- Add goals and score tracking.
- Implement faceoffs.
- Create the first playable 3v3 match.

### Phase 6: Lobby and Matchmaking
- Create third-person lobby.
- Add practice rink.
- Implement matchmaking.
- Implement dedicated match environments.
- Add post-match results.

### Phase 7: Progression
- Add player profiles.
- Add XP and currency.
- Add cosmetics.
- Add customization.
- Add shop and reward systems.

### Phase 8: Polish and Release
- UI improvements.
- Sound effects.
- Animations.
- Performance optimization.
- Mobile/controller compatibility evaluation.
- Testing and balancing.
- Launch preparation.

---

## 8. How I Want Claude to Work

Act as a collaborative technical developer.

I am the game designer and will make decisions about the gameplay direction.

I want you to:
- Explain technical decisions.
- Recommend better approaches when appropriate.
- Identify potential problems before implementation.
- Ask questions when important design decisions are unclear.
- Break large tasks into manageable milestones.
- Explain what scripts and systems you create.
- Test your work using available MCP tools.
- Be honest about limitations and unfinished functionality.

Do not silently change the game's core vision.

Do not overengineer early prototypes.

Do not implement multiple major systems simultaneously.

When proposing a feature, explain:
1. What it does.
2. How it will work.
3. Why this approach makes sense.
4. What its technical limitations are.

After completing a milestone, summarize:
- What was implemented.
- Which files were changed.
- What was tested.
- What still needs work.
- What you recommend doing next.

---

## 9. First Assignment

We are starting with a completely blank Roblox Studio project.

**Do not immediately start writing gameplay code.**

Your first assignment is:

1. Inspect the available Roblox Studio MCP tools and current project.
2. Research Puck gameplay using publicly available sources.
3. Investigate Roblox's current physics and networking capabilities.
4. Produce `docs/PUCK_GAMEPLAY_RESEARCH.md`.
5. Propose a technical architecture for our first playable prototype.
6. Recommend an implementation strategy for first-person skating, independent stick control, and puck physics.
7. Present the plan to me before implementing anything.

Our first actual development milestone will be a basic first-person hockey physics prototype.

Remember: The goal is not to build another generic Roblox hockey game.

**The goal is to make a genuinely satisfying physics-based hockey experience that people want to keep playing.**