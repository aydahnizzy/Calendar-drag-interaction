# SwiftUI Calendar Drag Interaction

A SwiftUI calendar view demonstrating fluid drag-and-drop for event blocks on iOS 18+. Events snap to 15-minute slots, display side-by-side when they overlap during a drag, and respond with haptic feedback at each time boundary.

---

## SwiftUI Drag Interactions — Rules & Patterns

Built from debugging a calendar event drag-and-drop inside a `ScrollView` on iOS 18+.

---

## The Six Rules

### 1. `value.translation`, never `value.location`

`value.location` is the finger's absolute position in the view's coordinate space.
Using it as your offset teleports the view's top-left corner to your finger on the first touch.
`value.translation` is the delta from where the gesture started — always use this.

```swift
DragGesture()
    .onChanged { value in
        offset = value.translation.height  // ✓
        offset = value.location.y          // ✗ jumps on first touch
    }
```

---

### 2. `coordinateSpace: .global` inside a ScrollView

Inside a `ScrollView`, the local coordinate space can shift between frames if the scroll position changes even slightly. This makes `value.translation` jump mid-drag.

`.global` anchors the measurement to the device screen, making it immune to any scroll movement.

```swift
DragGesture(minimumDistance: 5, coordinateSpace: .global)
```

---

### 3. Disable the ScrollView while dragging

Even with `.global`, the scroll view competes for the gesture. Freeze it the moment dragging begins.

```swift
@State private var isDragging = false

ScrollView { ... }
    .scrollDisabled(isDragging)
```

Set `isDragging = true` on the first `onChanged` call, reset it in `onEnded`.

---

### 4. Separate base position from live offset

Never mutate the model's position mid-drag. Keep two values:

- **`basePosition`** — the committed position, only updated on drop
- **`liveOffset`** — the raw in-flight translation, reset to 0 on drop

```swift
// Computed visual position during drag
var visualY: CGFloat {
    CGFloat(baseMinute) * ptPerMinute + (isDragging ? liveOffset : 0)
}

// onChanged
liveOffset = value.translation.height

// onEnded — commit and reset in one synchronous block
baseMinute = snappedValue(liveOffset)
liveOffset = 0
isDragging = false
```

This is also the fix for the "drag works the first time, jumps on the second drag" bug.
The second drag starts from the updated `basePosition`, so `liveOffset = 0` is the correct starting delta.

---

### 5. Commit synchronously in `onEnded` — no async callbacks

`withAnimation(completionCriteria: .logicallyComplete) { } completion: { }` defers your state reset asynchronously.
If the user picks up the view again before the spring settles, the old callback fires mid-drag and zeroes out `liveOffset`, causing a hard jump.

```swift
// ✓ — synchronous, safe
.onEnded { value in
    model.position = snapped(value.translation.height)
    liveOffset = 0
    isDragging = false
}

// ✗ — async callback can fire mid next drag
.onEnded { value in
    withAnimation(.spring(), completionCriteria: .logicallyComplete) {
        liveOffset = targetOffset
    } completion: {
        model.position = snapped(...)  // fires during the NEXT drag
        isDragging = false             // clears active drag state
    }
}
```

---

### 6. Never use `.animation(value:)` on a drag-driven view

`.animation(value:)` animates **all** property changes on the view whenever `value` fires — including your Y offset. If anything triggers that animation during drag (overlap detection, layout change), the position spring-animates instead of following the finger.

Use local `@State` for animated sub-properties and explicit `withAnimation` only inside `onChange`:

```swift
// ✗ — col change spring-animates Y too
.offset(x: xPos, y: dragY)
.animation(.spring(), value: col)

// ✓ — only X/width animates; dragY is always immediate
@State private var animCol: Int = 0

.onChange(of: col) { _, newCol in
    if isDragging {
        animCol = newCol              // instant during drag
    } else {
        withAnimation(.spring()) { animCol = newCol }
    }
}
.offset(x: xFromCol(animCol), y: dragY)
```

---

## Quick Checklist

| Rule | Prevents |
|---|---|
| `value.translation` not `.location` | Teleport on first touch |
| `coordinateSpace: .global` | ScrollView coordinate space shift |
| `.scrollDisabled(isDragging)` | Scroll gesture competing mid-drag |
| Separate `basePosition` + `liveOffset` | Second-drag jump |
| Synchronous commit in `onEnded` | Async callback firing during next drag |
| No `.animation(value:)` on drag views | Spring fighting the gesture |

---

## Minimal Template

```swift
struct DraggableView: View {
    @Binding var model: MyModel          // committed position lives here
    let isDragging: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat) -> Void

    var body: some View {
        MyContent()
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .onChanged { value in onChanged(value.translation.height) }
                    .onEnded   { value in onEnded(value.translation.height) }
            )
    }
}

// Parent view owns all drag state
struct ParentView: View {
    @State private var items: [MyModel] = [...]
    @State private var draggingID: UUID? = nil
    @State private var liveOffset: CGFloat = 0

    private func visualY(for item: MyModel) -> CGFloat {
        let base = CGFloat(item.position) * scale
        return item.id == draggingID ? base + liveOffset : base
    }

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                ForEach($items) { $item in
                    DraggableView(
                        model: $item,
                        isDragging: item.id == draggingID,
                        onChanged: { dy in
                            draggingID = item.id
                            liveOffset = dy
                        },
                        onEnded: { dy in
                            let snapped = snap(dy)
                            item.position = clamped(item.position + snapped)
                            draggingID = nil
                            liveOffset = 0
                        }
                    )
                    .offset(y: visualY(for: item))
                    .zIndex(item.id == draggingID ? 1 : 0)
                }
            }
        }
        .scrollDisabled(draggingID != nil)
    }
}
```
