import { addedFcmTokens } from "../notifications/reassign-fcm-token";

describe("addedFcmTokens", () => {
  it("returns no work when fcmTokens did not change", () => {
    expect(
      addedFcmTokens(
        { fcmTokens: ["token-a"], displayName: "Before" },
        { fcmTokens: ["token-a"], displayName: "After" },
      ),
    ).toEqual([]);
  });

  it("identifies only an added token", () => {
    expect(
      addedFcmTokens(
        { fcmTokens: ["token-a"] },
        { fcmTokens: ["token-a", "token-b"] },
      ),
    ).toEqual(["token-b"]);
  });

  it("does not reassign a removed token", () => {
    expect(
      addedFcmTokens(
        { fcmTokens: ["token-a", "token-b"] },
        { fcmTokens: ["token-a"] },
      ),
    ).toEqual([]);
  });
});
