/**
 * Tests for tools/browser-batch.js (Spec 033).
 *
 * The module registers "browser_batch" via globalThis.registerTool and
 * dispatches each sub-action via globalThis.executeTool. Both globals are
 * stubbed per test; the module is re-required fresh each time.
 */

"use strict";

// Load the module with a given executeTool stub; returns the registered handler.
function loadBatch(executeToolStub) {
    jest.resetModules();
    const registrations = {};
    globalThis.registerTool = (name, handler) => { registrations[name] = handler; };
    globalThis.executeTool = executeToolStub || jest.fn();
    require("../../ClaudeInSafari Extension/Resources/tools/browser-batch.js");
    return registrations["browser_batch"];
}

const ok = (name) => ({ result: { content: [{ type: "text", text: `${name}:done` }] } });

afterEach(() => {
    delete globalThis.registerTool;
    delete globalThis.executeTool;
});

describe("browser_batch", () => {
    // TB1: sequential success — actions run in order, outputs aggregated.
    test("TB1: runs actions sequentially and aggregates their output", async () => {
        const calls = [];
        const exec = jest.fn(async (name) => { calls.push(name); return ok(name); });
        const batch = loadBatch(exec);

        const out = await batch({
            actions: [
                { name: "navigate", input: { url: "https://x.com" } },
                { name: "get_page_text", input: {} },
            ],
        });

        expect(calls).toEqual(["navigate", "get_page_text"]);
        const text = out.content.map((b) => b.text).join("\n");
        expect(text).toContain("[1/2] navigate");
        expect(text).toContain("navigate:done");
        expect(text).toContain("[2/2] get_page_text");
        expect(text).toContain("get_page_text:done");
        expect(text).toMatch(/Batch complete: 2\/2/);
    });

    // TB2: stop on first error — later actions are not run; prior output kept.
    test("TB2: stops on the first error and preserves prior output", async () => {
        const calls = [];
        const exec = jest.fn(async (name) => {
            calls.push(name);
            if (name === "form_input") {
                return { error: { content: [{ type: "text", text: "bad ref" }] } };
            }
            return ok(name);
        });
        const batch = loadBatch(exec);

        const out = await batch({
            actions: [
                { name: "navigate", input: {} },
                { name: "form_input", input: {} },
                { name: "get_page_text", input: {} },
            ],
        });

        expect(calls).toEqual(["navigate", "form_input"]); // 3rd action NOT run
        const text = out.content.map((b) => b.text).join("\n");
        expect(text).toContain("navigate:done");           // prior output preserved
        expect(text).toMatch(/ERROR: action 2\/3 \(form_input\)/);
        expect(text).toContain("bad ref");
        expect(text).toMatch(/1 of 3 action\(s\) completed/);
    });

    // TB3: empty / missing actions array is rejected.
    test("TB3: rejects a missing or empty actions array", async () => {
        const batch = loadBatch(jest.fn());
        await expect(batch({})).rejects.toThrow(/non-empty 'actions'/);
        await expect(batch({ actions: [] })).rejects.toThrow(/non-empty 'actions'/);
    });

    // TB4: a malformed action (no string name) is rejected.
    test("TB4: rejects a malformed action", async () => {
        const batch = loadBatch(jest.fn());
        await expect(batch({ actions: [{ input: {} }] })).rejects.toThrow(/malformed/);
        await expect(batch({ actions: [{ name: 5 }] })).rejects.toThrow(/malformed/);
    });

    // TB5: nesting browser_batch is rejected.
    test("TB5: rejects a nested browser_batch", async () => {
        const exec = jest.fn();
        const batch = loadBatch(exec);
        await expect(batch({ actions: [{ name: "browser_batch", input: {} }] }))
            .rejects.toThrow(/cannot be nested/);
        expect(exec).not.toHaveBeenCalled();
    });

    // TB6: native-only tools are rejected up front, nothing executed.
    test("TB6: rejects native-only tools without executing the batch", async () => {
        for (const t of ["gif_creator", "upload_image", "file_upload"]) {
            const exec = jest.fn();
            const batch = loadBatch(exec);
            await expect(batch({ actions: [{ name: "navigate", input: {} }, { name: t, input: {} }] }))
                .rejects.toThrow(new RegExp(`does not support '${t}'`));
            expect(exec).not.toHaveBeenCalled(); // whole batch rejected before any run
        }
    });

    // TB7: computer screenshot/zoom rejected; other computer actions allowed.
    test("TB7: rejects computer screenshot/zoom but allows other actions", async () => {
        const rej = loadBatch(jest.fn());
        await expect(rej({ actions: [{ name: "computer", input: { action: "screenshot" } }] }))
            .rejects.toThrow(/screenshot/);
        await expect(rej({ actions: [{ name: "computer", input: { action: "zoom" } }] }))
            .rejects.toThrow(/zoom/);

        const exec = jest.fn(async () => ok("computer"));
        const batch = loadBatch(exec);
        await batch({ actions: [{ name: "computer", input: { action: "left_click", coordinate: [1, 2] } }] });
        expect(exec).toHaveBeenCalledWith("computer", { action: "left_click", coordinate: [1, 2] }, undefined);
    });

    // TB8: the execution context is threaded through to each sub-action.
    test("TB8: threads context to executeTool", async () => {
        const exec = jest.fn(async () => ok("navigate"));
        const batch = loadBatch(exec);
        const ctx = { clientId: "c1", tabGroupId: null };
        await batch({ actions: [{ name: "navigate", input: { url: "u" } }] }, ctx);
        expect(exec).toHaveBeenCalledWith("navigate", { url: "u" }, ctx);
    });
});
