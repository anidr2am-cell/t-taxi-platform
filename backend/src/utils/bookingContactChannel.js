'use strict';
const {normalizeMessengerType}=require('./customerMessengerFields');
function usable(channel){return channel.enabled!==false && (channel.code==='WHATSAPP' ? /^\+?[1-9]\d{6,14}$/.test(String(channel.phoneNumber||'').replace(/[\s()-]/g,'')) : channel.code==='WECHAT' ? Boolean(channel.qrImageUrl) : ['LINE','KAKAO','TELEGRAM'].includes(channel.code)&&/^https:\/\//i.test(channel.addUrl||''));}
function resolveBookingContactChannel(preference,settings={}){const channels=(settings.channels||[]).filter(usable);const type=normalizeMessengerType(preference);return channels.find(c=>c.code===type)?.code ?? channels.find(c=>c.code===settings.defaultChannel)?.code ?? channels[0]?.code ?? null;}
module.exports={resolveBookingContactChannel};
