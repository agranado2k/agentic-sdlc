# Deep Modules

From "A Philosophy of Software Design":

**Deep module** = small interface + lots of implementation

```mermaid
flowchart TB
    subgraph deep["Deep module"]
        di["Interface — a few methods, simple parameters"]
        dimpl["Implementation — the complex logic, hidden behind the interface"]
        di --- dimpl
    end
```

**Shallow module** = large interface + little implementation (avoid)

```mermaid
flowchart TB
    subgraph shallow["Shallow module"]
        si["Interface — many methods, complex parameters"]
        simpl["Implementation — thin; it mostly passes through"]
        si --- simpl
    end
```

The picture to hold: a deep module is a narrow top over a tall body, a
shallow one is a wide top over almost nothing. Callers pay for the width of
the top on every use; maintainers get the height of the body as locality.

When designing interfaces, ask:

- Can I reduce the number of methods?
- Can I simplify the parameters?
- Can I hide more complexity inside?
