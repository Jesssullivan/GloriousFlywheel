import { env } from "$env/dynamic/private";

export class GitLabAPIError extends Error {
  constructor(
    public status: number,
    message: string,
    public body?: unknown,
  ) {
    super(message);
    this.name = "GitLabAPIError";
  }
}

interface RequestOptions {
  method?: string;
  body?: unknown;
  headers?: Record<string, string>;
  params?: Record<string, string>;
}

export class GitLabClient {
  private baseUrl: string;
  private token: string;

  constructor(baseUrl?: string, token?: string) {
    this.baseUrl =
      (baseUrl ?? env.GITLAB_URL ?? "https://gitlab.com") + "/api/v4";
    this.token = token ?? env.GITLAB_TOKEN ?? "";
  }

  async request<T>(path: string, options: RequestOptions = {}): Promise<T> {
    const url = new URL(this.baseUrl + path);
    if (options.params) {
      for (const [key, value] of Object.entries(options.params)) {
        url.searchParams.set(key, value);
      }
    }

    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      ...options.headers,
    };

    if (this.token) {
      headers["PRIVATE-TOKEN"] = this.token;
    }

    const response = await fetch(url.toString(), {
      method: options.method ?? "GET",
      headers,
      body: options.body ? JSON.stringify(options.body) : undefined,
    });

    if (!response.ok) {
      const body = await response.text().catch(() => "");
      if (response.status === 429) {
        throw new GitLabAPIError(429, "Rate limited by GitLab API");
      }
      throw new GitLabAPIError(
        response.status,
        `GitLab API error: ${response.status}${body ? ` - ${body}` : ""}`,
        body,
      );
    }

    if (response.status === 204) {
      return undefined as T;
    }

    return response.json() as Promise<T>;
  }

  withToken(token: string): GitLabClient {
    return new GitLabClient(this.baseUrl.replace("/api/v4", ""), token);
  }
}

export const gitlab = new GitLabClient();
