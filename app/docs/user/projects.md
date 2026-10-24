---
title: Project Collaboration
description: Creating projects, managing members, inviting collaborators, working with resources, and enabling project tools and clientside access
keywords: project members collaboration resources documents invitations roles creator editor viewer pin reposition tools clientside client
---

# Project Collaboration

Projects live inside workspaces and provide a space for team collaboration on resources (documents and other content types).

> See project tools and Clientside drawn as wireframes in [Application Flows](/docs/developer/application-flows).

## Creating a Project

**Route:** `POST /workspaces/:slug/projects`

Provide a name and optional description. A URL-safe slug is generated automatically, unique within the workspace. The creator is assigned the **creator** project role and a `ProjectMembership` is created.

Workspace capacity limits apply — if the workspace has reached `max_projects`, creation is blocked.

## Project Roles

Project-level roles are simpler than workspace roles, using a three-tier enum:

| Role | Can edit resources | Can manage members | Assigned how |
|------|-------------------|-------------------|--------------|
| **Creator** | Yes | Yes | Automatically on creation |
| **Editor** | Yes | No | Invitation or member add |
| **Viewer** | No | No | Invitation or member add |

Project roles are checked via `ProjectMembership#role` (an enum), not via the JSON permissions system used at the workspace level.

## Managing Project Members

**Routes:** `/workspaces/:slug/projects/:slug/memberships`

### Adding Members

Select from existing workspace members. A user **must be a workspace member** before they can be added to a project — the `user_is_workspace_member` validation enforces this.

### Inviting External Users

**Route:** `POST /workspaces/:slug/projects/:slug/invitations`

Invite someone who isn't yet a workspace member:

1. Enter their email and choose a project role (editor or viewer).
2. The system sends an invitation email with a 7-day expiry.
3. When the invitee accepts, they become both a workspace member (with viewer role) and a project member (with the specified role).

This dual-level acceptance happens atomically in `Invitation#accept!`.

### Changing Roles

Update a member's project role between creator, editor, and viewer.

### Removing Members

Destroy the `ProjectMembership` record. The user remains a workspace member.

## Pinning Projects

Users can pin their favorite projects for quick access:

**Routes:** `POST /workspaces/:slug/projects/:slug/pin` (pin) and `DELETE` on the same path (unpin) — a singular end-state resource, so retried requests are idempotent rather than toggling.

The controller finds your membership via `Current.user` (never a URL param) to prevent IDOR attacks. Pinned projects appear first in the project list.

## Resources

Resources are the content items within a project. The system uses a polymorphic pattern:

```
Project → has_many :resources → belongs_to :resourceable (polymorphic)
```

### Documents

The default (and currently only) resource type. Documents use **Action Text** for rich text editing, with [Lexxy](https://github.com/basecamp/lexxy) as the editor:

- `Document` model holds just an ID and timestamps
- Rich text content lives in Action Text's `rich_texts` table via `has_rich_text :body`
- The `Resource` wrapper provides title, status, position, and creator tracking
- Unsaved edits survive a closed tab — see [Form drafts (developer)](/docs/developer/form-drafts)
- To describe an image for people who can't see it, move to it with the arrow keys (or click it), press **Alt+F10** to reach its toolbar, and choose **ALT**. An image left undescribed is skipped by screen readers, and its caption names the file

### Resource Status

| Status | Meaning |
|--------|---------|
| `draft` | Work in progress, visible to project members |
| `published` | Complete, ready for wider consumption |

### Ordering

Resources have a `position` field (integer, >= 0) and can be reordered:

**Route:** `PATCH /workspaces/:slug/projects/:slug/resources/:id/position` (`Workspaces::Projects::Resources::PositionsController#update`)

The `positioned` scope orders by position ascending.

### Deleting a Resource

A resource's page offers **Delete** to the people who may remove it: the person who wrote it, the project's creator, and the workspace's owners when they are members of the project. An owner can delete a resource they cannot edit, which is why the control sits on the resource's page rather than its edit page. Delete asks for confirmation first; a deleted resource leaves the project for everyone and is not listed anywhere afterwards, so the dialog says it can't be undone.

**Route:** `DELETE /workspaces/:slug/projects/:slug/resources/:id` (`Workspaces::Projects::ResourcesController#destroy`)

### Adding New Resource Types

See the [Extending](/docs/developer/extending) guide for how to add new resource types via the polymorphic pattern.

## Project Tools

Each project has an independently configurable set of **tools** — navigable sections of the project (for example, the docs area). Tools appear as a tab bar on the project home page.

**Configuration route:** `GET/PATCH /workspaces/:slug/projects/:slug/tools`
**Controller:** `Workspaces::Projects::ToolsController`

The available tool catalogue is defined in code via `ProjectTools::Registry` (see `app/lib/project_tools/`). Each `ProjectTools::Tool` entry declares a key, a route-helper name, and whether it is enabled by default. New tools are registered in `config/initializers/project_tools.rb` using `ProjectTools::Registry.register(...)`.

Per-project state is stored as a JSON array of key strings in `projects.enabled_tools`. The model exposes:

- `Project#tool_enabled?(key)` — boolean check for a single key
- `Project#tools` — returns the subset of `Registry.implemented` tools that are enabled for this project, in registry order

New projects receive the registry's default enabled set (`Registry.default_keys`). The only built-in tool currently shipped is `:docs`.

See [Project Tools](/docs/user/project-tools) for the full reference.

## Clientside (External Client Access)

A project can optionally expose a read-only **client area** to external users who are _not_ workspace members.

**Enabling clientside:**

`GET/PATCH /workspaces/:slug/projects/:slug/clientside`
`Controller: Workspaces::Projects::ClientsidesController`

Toggle the `clientside_enabled` flag on the project. When disabled, client invitations cannot be sent and the client area is inaccessible.

**Inviting clients:**

`GET /workspaces/:slug/projects/:slug/client_invitations/new`
`POST /workspaces/:slug/projects/:slug/client_invitations`
`Controller: Workspaces::Projects::ClientInvitationsController`

Send an invitation to an external email address and company name. The invitation flow reuses the shared `Invitation` bearer-token system — `Invitation.invite_client!` creates the record and sends the email.

**Client access model:**

Each accepted invitation creates a `ClientAccess` record linking the external `User` to the project. Clients are regular authenticated Users but are never workspace members — they hold no `Membership`, consume no seat, and are invisible to Pundit workspace policies. The relationship is tracked as `Project has_many :client_accesses`.

**What clients can see:**

Clients access the project through the separate `Clientside::` controller namespace. They can only see resources where `Resource#client_visible?` returns true — i.e. the resource is both `published` and `shared_with_client` (`resources.shared_with_client` column). The project's `client_visible_resources` helper returns this filtered, positioned set.

See [Clientside](/docs/user/clientside) for the full reference.

## Project Lifecycle

Like workspaces, projects are **Active** by default and can be **Archived** (reversible) or **Deleted** (permanent) by anyone who can manage the project. Projects have no lock state of their own — a locked workspace blocks its projects along with everything else.

### Archive (reversible)

**Route:** `POST /workspaces/:workspace_slug/projects/:slug/archival` (archive) · `DELETE .../archival` (restore)

Archiving moves a project out of the active list — "you can bring it back anytime from the **Archived** section." An archived project stays readable to its members and to external clients on shared resources (see [Clientside](/docs/user/clientside)). **Restore** returns it to Active.

### Delete (permanent)

**Route:** `DELETE /workspaces/:workspace_slug/projects/:slug`

Deleting is permanent, confirmed through a "Delete this project for good?" → "Delete forever" dialog (no name-typing, unlike deleting a whole workspace). Under the hood it is a soft delete (`Discardable`) — data is retained but hidden from every view. Deleting a workspace cascades this to all of its projects.

## Real-Time Updates

Projects broadcast changes via Turbo Streams:

- `ProjectMembership` broadcasts on create, update, and destroy
- `Resource` broadcasts changes to the project channel
- Connected users see updates in real time
