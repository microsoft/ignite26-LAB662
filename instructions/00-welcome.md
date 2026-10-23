@lab.Title

# Avoiding Agent Chaos: Design Your Enterprise Agent Governance Model

**LAB662 | Level 200 | 75 minutes | Audience: business and technical decision makers**

Welcome!

Everyone is building agents. In this lab you won't build any. **The agents are already built. Your job is to govern them.**

You'll start where an IT leader starts, with a view of every agent in the organization. Then you'll look closer at the agents one development team built.

| Tool | Who uses it | What it answers |
|---|---|---|
| **Microsoft Agent 365** (part of the Microsoft 365 admin center) | IT and AI administrators | "Which agents run across the whole organization, where did they come from, and who owns them?" |
| **Microsoft Foundry** (observability and governance, also called the Foundry Control Plane) | Developers and platform teams | "Are *our* agents working, what do they cost, and what are they allowed to do?" |

> [!Knowledge]
> **Which product wins?** Neither. That's the wrong question. Each product works on its own, and you don't need one to use the other. Used together, they give you one end-to-end view of agent governance, from what the developer configures to what IT governs across the organization.

### Your scenario: Caldova Pharmaceuticals

Caldova is a fictional pharmaceutical company. Teams across the business have been building agents in Copilot Studio and Microsoft Foundry, and some have been brought in from outside. Nobody has a complete list.

One team, Supply Chain, built four specialist agents in Microsoft Foundry to advise on a supply disruption. A planner wants to move production to a new supplier, **Northbank**, and speed up deliveries through the **Cedar** route. The agents give advice, but **none of them is allowed to commit the company to anything**.

| Foundry agent | Business owner | What it may do |
|---|---|---|
| **caldova-distribution** | Supply Chain Operations | Compare routes and recommend. It can't book shipments. |
| **caldova-capacity-planning** | Manufacturing Operations | Compare supplier capacity. It can't book capacity or authorize manufacturing. |
| **caldova-supplier-risk-monitor** | Supplier Assurance | Classify risk and recommend escalation. It can't block a supplier. |
| **caldova-approval-packet-reviewer** | Quality Governance | Check a change packet for completeness. It can't sign or approve. |

Two more Foundry agents, **guardrail-test-agent** and **guardrail-monitor-agent**, are set up for a guardrails exercise. These agents have already been used, so their activity, traces and evaluations are ready for you to explore.

> [!Note]
> All companies, people, agents, quantities and documents in this lab are fictional training data. Don't use them for real decisions.

### Lab outline

| Page | Business question | Time |
|---|---|---|
| 1. Sign in | | 5 min |
| 2. Agent 365: find every agent | "What agents do we have, where did they come from, and who owns them?" | 20 min |
| 3. Foundry: health, cost, guardrails and policies | "Are they working, what do they cost, and what's our minimum safety bar?" | 25 min |
| 4. Better together | "What happens when the two work together?" | 5 min |
| 5. Wrap-up | "What will we do on Monday?" | 5 min |

Select **Next** to begin.
