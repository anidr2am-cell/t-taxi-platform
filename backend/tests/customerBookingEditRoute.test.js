const test=require('node:test'),assert=require('node:assert/strict');
const {CustomerBookingEditService}=require('../src/services/customerBookingEdit.service');
const request=require('supertest');const app=require('../src/app');const container=require('../src/helpers/container');
test('customer edit route accepts only approved fields and never treats a booking number as authorization',async()=>{
 let calls=0;container.register('customerBookingEditService',()=>({run:async(number,user,token,input)=>{calls++;if(token!=='qa-only')throw Object.assign(Error('denied'),{statusCode:403,errorCode:'BOOKING_NOT_ACCESSIBLE'});return {canEdit:true,revision:'a'.repeat(64),changed:Boolean(input)};}}));
 const url='/api/v1/bookings/TX209901010218/customer-edit';assert.equal((await request(app).get(url)).status,403);
 const get=await request(app).get(url).set('X-Guest-Access-Token','qa-only');assert.equal(get.status,200);assert.equal(get.headers['cache-control'],'no-store');
 const before=calls;assert.equal((await request(app).patch(url).set('X-Guest-Access-Token','qa-only').send({revision:'a'.repeat(64),totalAmount:1})).status,400);assert.equal(calls,before);
 assert.equal((await request(app).patch(url).set('X-Guest-Access-Token','qa-only').send({revision:'a'.repeat(64),specialRequests:'QA'})).status,200);
});
