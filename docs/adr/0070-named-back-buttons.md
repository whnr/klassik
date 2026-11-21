# 0070. Back buttons show the destination name

Flo requested this in sz-rs30.1.105.23.
Replaces the back button name rules of [0038](0038-standard-tabs-and-the-cross-tab-back.md).

## Context

A chevron alone does not tell the listener where Back goes.
The original rule in [0018](0018-stack-and-back.md) names that destination.

## Decision

- Show the destination name beside the chevron on each page with a back control.
- Keep the native stack back button, its pages menu and its edge swipe.
- Give the native back bar item an explicit title through UIKit.
- Give cross-tab toolbar buttons the same visible destination name.
- Keep the bar title hidden under [0023](0023-no-title-in-the-bar.md).

## Consequences

Every stack page supplies a short name for the next page's back control.
Long names use the available width. The system controls truncation.
The UI walk checks visible button width, destination labels, the pages menu and the edge swipe.
If the native control cannot show the name, Flo must decide again.
