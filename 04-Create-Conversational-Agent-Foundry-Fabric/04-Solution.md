# Solution Challenge 04 - Create a Conversational Agent in AI Foundry Integrated with Microsoft Fabric

Step-by-step guide to enable a conversational agent from AI Foundry integrated with the Microsoft Fabric Data Agent.

### Objective 🎯
- Design a conversational agent in AI Foundry integrated with Microsoft Fabric.
- Connect the agent to a Data Agent associated with the semantic model/Gold tables.
- Configure intents and prompts aimed at real business questions.
- Validate that the agent answers in natural language without showing code or technical syntax.
- (Optional) Publish the agent for analyst use in Copilot, Power BI, or AI Foundry.

---

## Prerequisites

- Semantic model, Data Agent, and value dashboard (Gold) - see `03-Solution.md`.

## Steps

### 1 - Create the Agent in Foundry

1. To create an agent in Foundry, you need access to a Foundry resource within a project (prerequisites). Go to your Azure AI Foundry resource from the Azure subscription or sign in with your authorized user at [AI Foundry](https://ai.azure.com/). Enable the new Foundry experience, as it provides a simpler and more intuitive environment.

![New Foundry](/img/new_foundry.png)

2. Select your project → from the welcome menu → **Start building** → **Create agent** → in **Agent Name** assign a descriptive and unique name, for example: `Contoso-Virtual-Analyst`.

![Foundry-Start](/img/foundry-start.png)

3. In the agent menu → **Playground** → select the model created as part of the prerequisites and click **Save**. **gpt-4o** is now marked *Legacy* in the model catalog; use a current chat model such as **gpt-6-luna** (Global Standard, default quota was enough for all challenges).

> If nothing was pre-provisioned, signing in to [ai.azure.com](https://ai.azure.com/) for the first time creates a Foundry resource and project for you automatically.

✅ **Expected result:** The agent is created and configured for conversational interaction.

![Foundry-Agent](/img/foundry-agent.png)


### 2 - Connect the Agent to the Fabric Data Agent

> ⚠️ **The Fabric Data Agent tool is deprecated on November 6, 2026** and its tile is already disabled in the Foundry tool catalog. Use its replacement, **Fabric IQ (OneLake Catalog)**, as described below. You no longer need to copy workspace or artifact IDs.

1. **Publish the data agent in Fabric.** Open the data agent → **⋯** → **Publish**. (The disk icon on the ribbon is *Save as*, which makes a copy; data agents save automatically.) Fill in the publish description. Foundry uses it to decide when to call the agent, so say what data it has and which questions it answers.

2. **Verify the data agent's scope in Fabric.** Check that it's connected to the **Gold semantic model** or the tables it needs, for example:
   - `gold.business_operations`
   - `gold.credit_score`
   - `semantic model`

   Scope each data agent to only the tables its role needs. A table that isn't selected can't be queried, even if the instructions are ignored.

3. **Add the tool in Foundry.** In the agent's **Playground** → **Tools** → **Add** → **Add tools**, search for "fabric", select **Fabric IQ (OneLake Catalog)** → **Add tool**.

4. **Pick the data agent.** The OneLake Catalog picker lists the Fabric items you can access. Select your published data agent → **Add**. Foundry creates the project connection for you.

5. **Name the tool in the instructions** (next section): say which data agent is connected and which questions it handles. The model decides whether to call a tool from this text.

6. **Save.** In the new Foundry experience, every save becomes the agent's active version.

**What happens underneath:** the tool appears in the agent's YAML as `type: fabric_iq_preview`, with a `project_connection_id`, a `server_url` and `require_approval: never`. It's provided through an MCP server: at run time the agent first lists the tools, then calls the data agent. Queries run **as the signed-in user** (identity passthrough), so anyone who chats with the Foundry agent needs Read access to the data agent and its semantic model.

**Also check:** new agents start with an auto-created `<agent-name>-toolbox` that contains **Web search**. If this agent should only answer from internal data, remove Web search from its tools.

> The screenshots `fabric-tool.png` and `workspace-artifact.png` from the previous version of this step showed the deprecated connector and are no longer used.

✅ **Expected result:** The Foundry agent is connected to the Fabric Data Agent.


![Foundry-Agent](/img/fabric-tools.png)


### 3 - Define Guiding Intents and Prompts

1. Add instructions that help the agent understand what it should do. This configuration, often called a **System Prompt**, tells the agent how it should act, what tasks to perform, and how to format responses (tone, etc.). In this case, orient it toward the Fabric Data Agent.

In **Instructions**, add clear, concise, structured directions, then save the agent configuration again. Here is an example:

```
# Role and Context
You are an operational analytics assistant with access to
Contoso transaction and product data.

# Data Source
You have access to updated data from the Fabric Data Agent named 'Contoso Data Agent' containing:
- business_operations (transaction and product tables)

# Expected Behavior
1. Always consult the data before answering factual questions
2. If you cannot find information in the data, say so clearly
3. Cite specific sources when using data information
4. Maintain a tone [professional and technical as needed]

# Restrictions
- Do not invent information that is not in the data
- Always validate dates and numbers before reporting them

# Response Format
- Use tables for numeric data
- Include context when relevant
- Be concise but complete
```

![Foundry-Agent](/img/sys-prompt.png)


### 4 - Define Guiding Intents and Prompts

1. Now try creating `intents` or queries that reflect Contoso’s analytical needs. To do this, open the gear icon ⚙️ in the top right corner of the chat window.
   In the menu, complete the following:

   - **Display name**: so users identify the agent with a familiar name
   - **Description**: an optional description of what the agent does and how to use it
   - **Starter Prompts**: example intents for the agent’s context. These will appear as suggestions for the user.

```
"Which sales channel generates the most revenue?"
"Which category has the most valuable products?"
"What is the total commercial value by brand?"
```

Save the configuration.

![Foundry-Agent](/img/starter-prompts.png)


### 5 - Validate the Agent with Real Questions

1. In the chat bar, ask questions to validate the responses generated. You can select questions from the `starter prompts` list or use your own queries.

✅ **Expected result:** The agent understands business questions and responds contextually. If it lacks precision, adjust the instructions and test again.

![Foundry-Agent](/img/output-prompt.png)

### 6 - Publish and Enable the Agent

Once the agent is validated and demonstrates accurate behavior, publish it so it can be exported or made available through channels such as Teams and M365 Copilot.

1. In the upper right corner, select the **Publish** button. This lets you enable the agent in Teams and M365 Copilot channels, where corporate users can use it without direct access to Foundry or Microsoft Fabric. You can also configure access and groups.

![Foundry-Agent](/img/publish.png)

2. (Optional) If you have access, you can publish the agent to M365 and Teams. For that, Azure Bot Service must be enabled, which acts as middleware between the agent and the frontend layer (Teams, 365).
   Complete the requested configuration in the menu and continue through the 365 ecosystem for validation.

![Foundry-Agent](/img/optional-365.png)

3. Once published locally in Foundry, view the agent in `Preview`, which is a simulated view of a final application.

![Foundry-Agent](/img/preview.png)

![Foundry-Agent](/img/preview2.png)

✅ **Expected result:** The agent is active and available for natural language queries.
