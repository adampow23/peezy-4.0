# Peezy Admin Dashboard — Design Doc
**Date**: 2026-04-14  
**Status**: Approved  
**Output**: `public/admin/index.html`

## Context & Goals
Internal web-based command center for Peezy concierge staff. Replaces the mobile-only React prototype. Connects to Firebase (Firestore + Auth). Staff use this to handle support chats, vendor workflows, concierge tasks, and customer profiles.

## Delivery
Single self-contained HTML file — React + Babel via CDN, Firebase compat SDK via CDN. Deployed to Firebase Hosting at `/admin`. No build step required.

## Layout — 3 Column
```
[Sidebar 220px] | [List 360px] | [Detail flex-1]
```
- **Sidebar**: Logo, nav items (Home/Chat/Tasks/Vendor/Customers), pending badge counts, admin user + sign out
- **List panel**: Filtered feed with search; Home shows Active + Needs Attention groups
- **Detail panel**: Item detail, customer profile, quote sheet, or home stats when nothing selected

## Auth
Firebase email/password gate. Full-screen login card before any content loads. Falls back to demo mode if Firebase config is not filled in.

## Design Tokens
- **Font**: Geist + Geist Mono (technical, command-center)
- **Theme**: Dark — bg0: `#07090d`, bg1: `#0b0d12`, bg2: `#0f1117`
- **Brand**: `#fbbf24` amber
- **Type colors**: red=support, purple=vendor, blue=task/concierge, yellow=inventory
- **No emoji icons** — SVG stroke icons in nav; glowing 6px dot indicators per type

## Type Indicators
- Small 6px circle with `box-shadow` color glow — replaces colored emoji squares
- Selected list item gets a 2px left border in type color
- Type pill (uppercase label, subtle border + bg tint) shown in each row

## Components
- `LoginScreen` — centered card, email+password, Firebase Auth
- `Sidebar` — nav + badge counts + user/signout
- `ListPanel` — item feed or customer list with search
- `ItemRow` / `CustomerRow` — list item components
- `ItemDetail` — chat view or task detail with status actions
- `CustomerProfile` — full profile: contact, assessment, tasks, inventory, activity
- `QuoteSheet` — clean copy-ready mover quote, no PII
- `HomeStats` — stats grid shown in detail panel when nav=home
