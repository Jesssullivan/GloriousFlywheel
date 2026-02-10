import {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse,
  type VerifiedRegistrationResponse,
  type VerifiedAuthenticationResponse,
} from "@simplewebauthn/server";
import type {
  RegistrationResponseJSON,
  AuthenticationResponseJSON,
  AuthenticatorTransportFuture,
} from "@simplewebauthn/server";
import { env } from "$env/dynamic/private";
import {
  getCredentialsByUserId,
  getCredentialByCredentialId,
  saveCredential,
  updateCounter,
} from "./webauthn-store";

// In-memory challenge store (acceptable for replicas=1)
const challenges = new Map<string, { challenge: string; expires: number }>();
const CHALLENGE_TTL = 5 * 60 * 1000; // 5 minutes

function getConfig() {
  return {
    rpID: env.WEBAUTHN_RP_ID ?? "localhost",
    rpName: env.WEBAUTHN_RP_NAME ?? "Runner Dashboard",
    origin: env.WEBAUTHN_ORIGIN ?? `https://${env.WEBAUTHN_RP_ID ?? "localhost"}`,
  };
}

function storeChallenge(key: string, challenge: string) {
  challenges.set(key, { challenge, expires: Date.now() + CHALLENGE_TTL });
  // Lazy cleanup
  for (const [k, v] of challenges) {
    if (v.expires < Date.now()) challenges.delete(k);
  }
}

function consumeChallenge(key: string): string | null {
  const entry = challenges.get(key);
  if (!entry || entry.expires < Date.now()) {
    challenges.delete(key);
    return null;
  }
  challenges.delete(key);
  return entry.challenge;
}

export async function startRegistration(userId: number, username: string) {
  const config = getConfig();
  const existingCreds = await getCredentialsByUserId(userId);

  const options = await generateRegistrationOptions({
    rpName: config.rpName,
    rpID: config.rpID,
    userName: username,
    attestationType: "none",
    excludeCredentials: existingCreds.map((c) => ({
      id: c.credential_id,
      transports: c.transports as AuthenticatorTransportFuture[],
    })),
    authenticatorSelection: {
      residentKey: "preferred",
      userVerification: "preferred",
    },
  });

  storeChallenge(`reg:${userId}`, options.challenge);
  return options;
}

export async function finishRegistration(
  userId: number,
  username: string,
  response: RegistrationResponseJSON,
): Promise<VerifiedRegistrationResponse> {
  const config = getConfig();
  const expectedChallenge = consumeChallenge(`reg:${userId}`);
  if (!expectedChallenge) {
    throw new Error("Registration challenge expired or not found");
  }

  const verification = await verifyRegistrationResponse({
    response,
    expectedChallenge,
    expectedOrigin: config.origin,
    expectedRPID: config.rpID,
  });

  if (verification.verified && verification.registrationInfo) {
    const { credential, credentialDeviceType, credentialBackedUp } =
      verification.registrationInfo;

    await saveCredential({
      user_id: userId,
      username,
      credential_id: credential.id,
      public_key: Buffer.from(credential.publicKey),
      counter: credential.counter,
      transports: (response.response.transports ?? []) as string[],
      device_type: credentialDeviceType,
      backed_up: credentialBackedUp,
    });
  }

  return verification;
}

export async function startAuthentication() {
  const config = getConfig();
  const options = await generateAuthenticationOptions({
    rpID: config.rpID,
    userVerification: "preferred",
  });

  storeChallenge(`auth:${options.challenge}`, options.challenge);
  return options;
}

export async function finishAuthentication(
  response: AuthenticationResponseJSON,
): Promise<{
  verified: boolean;
  userId: number;
  username: string;
}> {
  const config = getConfig();

  const credential = await getCredentialByCredentialId(response.id);
  if (!credential) {
    throw new Error("Credential not found");
  }

  const expectedChallenge = consumeChallenge(`auth:${response.rawId}`);
  // Fallback: try finding by iterating challenges (discoverable credentials)
  let challenge = expectedChallenge;
  if (!challenge) {
    for (const [key, entry] of challenges) {
      if (key.startsWith("auth:") && entry.expires > Date.now()) {
        challenge = entry.challenge;
        challenges.delete(key);
        break;
      }
    }
  }
  if (!challenge) {
    throw new Error("Authentication challenge expired or not found");
  }

  const verification: VerifiedAuthenticationResponse =
    await verifyAuthenticationResponse({
      response,
      expectedChallenge: challenge,
      expectedOrigin: config.origin,
      expectedRPID: config.rpID,
      credential: {
        id: credential.credential_id,
        publicKey: new Uint8Array(credential.public_key),
        counter: credential.counter,
        transports: credential.transports as AuthenticatorTransportFuture[],
      },
    });

  if (verification.verified) {
    await updateCounter(
      credential.credential_id,
      verification.authenticationInfo.newCounter,
    );
  }

  return {
    verified: verification.verified,
    userId: credential.user_id,
    username: credential.username,
  };
}
