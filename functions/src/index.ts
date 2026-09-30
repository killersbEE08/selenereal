import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";

initializeApp();
setGlobalOptions({ region: "asia-south1", maxInstances: 20 });

export { analyzePalm } from "./palm";
export { startTarotReading } from "./tarot";
export { sendChatMessage } from "./chat";
export { getHoroscope, prewarmHoroscopes } from "./horoscope";
export { getCardInsight, getDailyCard } from "./cards";
export { deleteMyData, deletePalmPhotos, cleanupPalmPhotos, revenueCatWebhook, syncPremium, devSetPremium } from "./account";
export { createDodoCheckout, dodoPortal, syncDodoPremium, dodoWebhook } from "./dodo";
