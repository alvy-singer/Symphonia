import { NextResponse } from "next/server";

export const SERVICE_URL = process.env.SYMPHONIA_SERVICE_URL ?? "http://127.0.0.1:4057";

const ACTOR_HEADER_NAMES = [
  "x-symphonia-actor",
  "x-symphonia-actor-id",
  "x-symphonia-role",
] as const;

export async function proxyToSymphoniaService(
  path: string,
  init: RequestInit = {},
  request?: Request,
): Promise<NextResponse> {
  try {
    const headers = new Headers(init.headers);
    forwardActorHeaders(headers, request);

    if (init.body && !headers.has("content-type")) {
      headers.set("content-type", "application/json");
    }

    const response = await fetch(`${SERVICE_URL}${path}`, {
      ...init,
      cache: "no-store",
      headers,
    });
    const body = await response.text();

    return new NextResponse(body || "{}", {
      status: response.status,
      headers: {
        "content-type": response.headers.get("content-type") ?? "application/json",
      },
    });
  } catch {
    return NextResponse.json(
      { error: "Symphonía service is not running. Start the Elixir service and try again." },
      { status: 503 },
    );
  }
}

export async function jsonBody(request: Request): Promise<string> {
  return JSON.stringify(await request.json());
}

export async function serviceJson<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  if (init.body && !headers.has("content-type")) {
    headers.set("content-type", "application/json");
  }

  const response = await fetch(`${SERVICE_URL}${path}`, {
    ...init,
    cache: "no-store",
    headers,
  });
  const payload = (await response.json().catch(() => ({}))) as T & { error?: string };

  if (!response.ok) {
    throw new Error(payload.error ?? "Symphonía service request failed.");
  }

  return payload;
}

function forwardActorHeaders(headers: Headers, request?: Request): void {
  if (!request) return;

  for (const name of ACTOR_HEADER_NAMES) {
    const value = request.headers.get(name);
    if (value) headers.set(name, value);
  }
}
