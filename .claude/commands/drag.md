# /drag — SwiftUI Drag Interaction Checklist

When the user asks you to build a drag interaction in SwiftUI, apply these rules before writing any code. Read `docs/swiftui-drag-interactions.md` for the full rationale behind each rule.

## Pre-flight checklist

Before implementing, confirm answers to:
1. Is the draggable view inside a `ScrollView`?
2. Is the drag vertical, horizontal, or 2D?
3. Should it snap to a grid? What interval?
4. Can multiple items be dragged (or just one at a time)?

## Rules to apply — no exceptions

1. **`value.translation` only** — never `value.location`. Check the gesture handler and fail loudly if `.location` is used anywhere.

2. **`coordinateSpace: .global`** — always set this on `DragGesture` when the draggable is inside a `ScrollView`.
   ```swift
   DragGesture(minimumDistance: 5, coordinateSpace: .global)
   ```

3. **`.scrollDisabled(draggingID != nil)`** — attach to the `ScrollView`. The flag must flip on the *first* `onChanged` call.

4. **Separate base + offset** — the model's committed position must not change during drag. Use:
   - `basePosition` (from model, only written in `onEnded`)
   - `liveOffset` (raw translation, reset to 0 in `onEnded`)
   - Visual position = `basePosition + liveOffset`

5. **Synchronous commit in `onEnded`** — write the new model position, clear `liveOffset`, clear `draggingID` all in the same synchronous block. No `withAnimation(completionCriteria:)` with a deferred completion.

6. **No `.animation(value:)` on drag-driven views** — use `@State` + `withAnimation` inside `onChange` for any animated sub-properties (e.g. column assignment). The drag-axis offset must never be wrapped in any animation transaction.

## Architecture pattern

```
ParentView (@State: draggingID, liveOffset)
  └─ ScrollView (.scrollDisabled)
       └─ ZStack
            └─ ForEach
                 └─ ContainerView (.offset(y: visualY), .zIndex)
                      └─ DraggableContent (.gesture)
```

- Parent owns `draggingID` and `liveOffset`
- Container computes and applies `.offset` — no animation modifier on the offset itself
- Draggable content owns only the `.gesture` and fires callbacks up

## What NOT to do

- Do not put `liveOffset` inside the draggable child view — it needs to be in the parent to drive sibling layout (e.g. overlap detection)
- Do not animate `liveOffset` changes — they must be immediate to follow the finger
- Do not defer model commits to an async callback
- Do not use `.animation(value:)` on any view whose position is driven by `liveOffset`
