"use client";

import { useActionState } from "react";
import { login, type LoginState } from "./actions";

export function LoginForm() {
  const [state, action, pending] = useActionState<LoginState, FormData>(login, {});
  return (
    <form action={action} className="space-y-5" noValidate>
      <div>
        <label htmlFor="email" className="mb-1 block text-lg font-semibold">
          Email
        </label>
        <input
          id="email"
          name="email"
          type="email"
          autoComplete="username"
          required
          className="w-full rounded-md border-2 border-line bg-white px-4 py-3 text-lg"
        />
      </div>
      <div>
        <label htmlFor="password" className="mb-1 block text-lg font-semibold">
          Password
        </label>
        <input
          id="password"
          name="password"
          type="password"
          autoComplete="current-password"
          required
          className="w-full rounded-md border-2 border-line bg-white px-4 py-3 text-lg"
        />
      </div>
      {state.error && (
        <p role="alert" className="rounded-md bg-danger-bg px-4 py-3 text-danger">
          {state.error}
        </p>
      )}
      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-md bg-brand px-4 py-3 text-lg font-semibold text-white hover:bg-brand-dark disabled:opacity-60"
      >
        {pending ? "Sedang masuk..." : "Masuk"}
      </button>
    </form>
  );
}
