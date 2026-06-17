from typing import Any, Protocol


class AdapterFailure(RuntimeError):
    """Raised when an external model adapter cannot return a valid result."""


class BaseAdapter(Protocol):
    async def call(self, **kwargs: Any) -> dict[str, Any]:
        ...

