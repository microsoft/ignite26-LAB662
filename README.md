## Before you're done

This repo has been created for your Microsoft Ignite 2026 session. Here's how to get it ready.

**Easiest path — use the agent (recommended):**

- Open GitHub Copilot Chat and say `help me initialize repo`. The agent will walk you through getting the README populated.
- When you're ready to publish, say `help me finalize repo`. The agent will clean up unused folders, validate everything, and remove this "Before you're done" section and other extra stuff that attendees don't need to see.
- Curious how it works? Read the [agent workflow](.github/AGENT-WORKFLOW.md).

**Doing it manually?**

Fill in the sections below yourself, then:

- Delete any placeholder folders you don't need (`data/`, `infra/`, etc.)
- Delete this "Before you're done" section
- Delete `.github/agents/`, `.github/tests/`, `.github/copilot-instructions.md`, and `.github/AGENT-WORKFLOW.md` — these are template tooling, not part of your published repo

**Folder conventions:**

- Attendee step-by-step guidance goes in `instructions/`. If you use MkDocs or a docs site instead, put it in `docs/` and link to it from this README.
- Reference material and background reading go in `docs/`.
- You can add a `.devcontainer/` folder if needed.

---

<a name="start-building"></a>

<p align="center">
<img src="img/banner-ignite-26.png" alt="Microsoft Ignite 2026" width="100%"/>
</p>

# [Microsoft Ignite 2026](https://ignite.microsoft.com)

## 🔥LAB662: Design your enterprise agent governance model
### Session description

Are governance gaps slowing AI at scale, leaving business leaders like yourself struggling to manage risk amidst fragmented tools and unclear guidance? In this no-code lab, explore how Microsoft Foundry, Copilot Studio, and Agent 365 can help unify governance and security across agents, apps, data, and models. Compare choices, map controls to business priorities, and leave with an actionable path to scale AI agents with confidence.

### 🚀 Getting started

#### In a guided session

If you're following along during a live session:

1. Open the [lab welcome and scenario](instructions/00-welcome.md).
2. Follow the [sign-in instructions](instructions/01-sign-in.md) using the accounts provided in your lab environment's **Resources** tab.
3. Follow your instructor through [Agent 365](instructions/02-agent-365.md), [Microsoft Foundry](instructions/03-foundry.md), [Better together](instructions/04-better-together.md), and the [wrap-up](instructions/05-wrap-up.md).

#### On your own

If you're learning at your own pace:

1. Read the [lab welcome and scenario](instructions/00-welcome.md). This no-code lab only requires a browser.
2. Use the lab launch link below when it becomes available. The exercises require the provided lab accounts and preconfigured agents; cloning this repository does not provision them.
3. Follow the [sign-in instructions](instructions/01-sign-in.md), then work through [Agent 365](instructions/02-agent-365.md), [Microsoft Foundry](instructions/03-foundry.md), [Better together](instructions/04-better-together.md), and the [wrap-up](instructions/05-wrap-up.md).

#### Session resources

| Resource | Availability |
|----------|--------------|
| Launch lab | Coming soon — add the lab launch URL |
| Session slides | Coming soon — add the slides URL |
| Session recording | Coming soon — add the recording URL |

### 🎯 Learning outcomes

By the end of this session, you will be able to:

- Use Microsoft Agent 365 to discover agents across an organization and establish accountable ownership.
- Explain how developers use Microsoft Foundry to interpret Foundry agent health, costs, guardrails, and policies.
- Explain how Microsoft Agent 365 and Microsoft Foundry work together to connect enterprise-wide oversight with developer controls.

### 💻 Technologies used

- Microsoft Agent 365
- Microsoft Foundry

### 📚 Continue your learning

Pick your next step based on your learning style:

| Resource | What you'll get |
|----------|-----------------|
| **[Ignite 2026 Next Steps](https://aka.ms/ignite26-next-steps)** | Additional session repos and materials from Microsoft Ignite 2026 |
| **[Microsoft AI Skills Navigator](https://aka.ms/ignite26-asn)** | Discover AI skills, learning paths, and resources for your next step |
| **[Microsoft Learn](https://aka.ms/ignite26-learn)** | Official documentation and guided learning paths on these topics |
| **[Microsoft Foundry Community](https://aka.ms/MicrosoftFoundryDiscord-Ignite26)** | Connect with other learners and experts in our Discord community |

### 🌟 Microsoft Learn MCP Server

<!-- Remove this section if the Microsoft Learn MCP Server is not relevant to the session. -->

The Microsoft Learn MCP Server gives your AI agent direct access to Microsoft's official documentation — grounded, up-to-date answers about the topics in this session.

**GitHub Copilot CLI** — Install with:

```shell
copilot plugin install microsoftdocs/mcp
```

**VS Code** — One-click install:  
[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install_Microsoft_Learn_MCP-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect/mcp/install?name=microsoft-learn&config=%7B%22type%22%3A%22http%22%2C%22url%22%3A%22https%3A%2F%2Flearn.microsoft.com%2Fapi%2Fmcp%22%7D)

For more information, visit the [Learn MCP Server repo](https://aka.ms/learnmcp).

### 👥 Content owners

<!-- TODO: Add yourself as a content owner
1. Change the src in the image tag to {your github url}.png
2. Change INSERT NAME HERE to your name
3. Change the github url in the final href to your url. -->

<table>
<tr>
    <td align="center"><a href="https://github.com/amynic">
        <img src="https://github.com/amynic.png" width="100px;" alt="Amy Boyd"/><br />
        <sub><b>Amy Boyd</b></sub></a><br />
            <a href="https://github.com/amynic" title="talk">📢</a>
    </td>
    <td align="center"><a href="https://github.com/BethanyJep">
        <img src="https://github.com/BethanyJep.png" width="100px;" alt="Bethany Jepchumba"/><br />
        <sub><b>Bethany Jepchumba</b></sub></a><br />
            <a href="https://github.com/BethanyJep" title="talk">📢</a>
    </td>
    <td align="center"><a href="https://github.com/DonaSarkar">
        <img src="https://github.com/DonaSarkar.png" width="100px;" alt="Dona Sarkar"/><br />
        <sub><b>Dona Sarkar</b></sub></a><br />
            <a href="https://github.com/DonaSarkar" title="talk">📢</a>
    </td>
</tr></table>

### ⚖️ Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow [Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general). Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.

Any use of third-party trademarks or logos are subject to those third-party's policies.
