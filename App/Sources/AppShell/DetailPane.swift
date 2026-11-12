// A detail shown in a split view's detail column or an inspector instead of a sheet (docs/specs/ADAPTIVE_LAYOUT.md).
// The screen that owns the pane presents the editors (`edit`), so a size change that swaps pane <-> sheet never tears
// down an editor with unsaved changes: the editor sheet hangs on the screen's root, which survives the swap.

/// Callbacks of a detail pane; `nil` in a detail view = today's sheet / pushed form.
struct DetailPane {
    /// Leaves the pane (it has no Close button; a deleted item clears the selection).
    let close: () -> Void
    /// Opens the item's editor from the owning screen.
    let edit: () -> Void
}
