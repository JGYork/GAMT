package BluetreeCommit;

// This is effectively a clone of CommitIfc, but with the ability to also proxy
// data back from the ack signal.

// This file contains quite...a lot...
// This created CommitClient and CommitServer, modified in order for the Ack signal
// to also accept a data parameter.

// It also defines a CommitPFClient and CommitPFServer, which are like above, with an
// additional two lines. These are used to also relay prefetches seperately, and also
// a signal to notify of new available traffic.
// The available traffic signal is used with an arbiter, since some need to have information
// on whether a new packet is available.

// This lastly defines connections. CommitClient can connect to CommitServer, and vice versa.
// These can also connect to standard Clients and Servers. In this case, the ack signal will 
// always have a data payload of 0.

// CommitPFClients cannot currently connect to CommitServers, but this is simple to add. There's
// just no need for it for now.

// CommitPFClient CAN however connect to Server. For now, the prefetch line is ignored. 
// A CommitPFClient will only connect the standard request/response lines to a standard Server. 
// The newRequest line is NOT relayed.

// CommitPFServer CAN connect to a Client. This is done with a small shim. The ToRecvCommitPF typeclass
// is used for this. This is like ToRecvCommit with a FIFO, however, when a packet is admitted into the
// internal FIFO, it will ping the given PulseWire. This PulseWire is then used in the mkConnection logic
// in order to notify the CommitPFServer of a new request.

// Lastly, we define simpler typedefs to wrap up Bluetree transactions.

// No exports...just export everything...

import Bluetree2::*;
import Connectable::*;
import GetPut::*;
import FIFO::*;
import FIFOF::*;
import ClientServer::*;

typedef UInt#(8) AckType;

// The raw interfaces
interface SendCommit#(type a);
    method a dataout;
    
    (* always_ready *)
    method Action ack(AckType data);
endinterface

interface RecvCommit#(type a);
    (* always_ready *)
    method Action datain(a data);
    (* always_ready *)
    method Maybe#(AckType) accept;
endinterface

// Aggregate client/server interfaces
interface CommitClient#(type req, type resp);
    interface SendCommit#(req) request;
    interface RecvCommit#(resp) response;
endinterface

interface CommitServer#(type req, type resp);
    interface RecvCommit#(req) request;
    interface SendCommit#(resp) response;
endinterface

// Interfaces with two request lines.
// These are to split out prefetch requests into
// their own queues.
interface CommitPFClient#(type req, type resp);
    interface SendCommit#(req) request;
    interface SendCommit#(req) pfRequest;
    interface RecvCommit#(resp) response;
    interface Get#(UInt#(2)) newRequest;
endinterface

interface CommitPFServer#(type req, type resp);
    interface RecvCommit#(req) request;
    interface RecvCommit#(req) pfRequest;
    interface SendCommit#(resp) response;
    interface Put#(UInt#(2)) newRequest;
endinterface

// Connect up raw interfaces
instance Connectable#(SendCommit#(a), RecvCommit#(a));
    module mkConnection#(SendCommit#(a) s, RecvCommit#(a) r)(Empty);
    	(* fire_when_enabled *)
    	rule connectData;
    	    r.datain(s.dataout);
    	endrule
    	
    	(* fire_when_enabled *)
    	rule connectAck(r.accept matches tagged Valid .x);
    	    s.ack(x);
    	endrule
    endmodule
endinstance

instance Connectable#(RecvCommit#(a), SendCommit#(a));
    module mkConnection#(RecvCommit#(a) r, SendCommit#(a) s)(Empty);
    	(* hide *)
    	let _x <- mkConnection(s, r);
    endmodule
endinstance

// Connect up client/server interfaces
instance Connectable#(CommitClient#(a, b), CommitServer#(a, b));
    module mkConnection#(CommitClient#(a, b) c, CommitServer#(a, b) s)(Empty);
        let req <- mkConnection(c.request, s.request);
        let resp <- mkConnection(c.response, s.response);
    endmodule
endinstance

instance Connectable#(CommitServer#(a, b), CommitClient#(a, b));
    module mkConnection#(CommitServer#(a, b) s, CommitClient#(a, b) c)(Empty);
        (* hide *)
        let _x <- mkConnection(c, s);
    endmodule
endinstance

instance Connectable#(CommitPFClient#(a, b), CommitPFServer#(a, b));
    module mkConnection#(CommitPFClient#(a, b) c, CommitPFServer#(a, b) s)(Empty);
        let req <- mkConnection(c.request, s.request);
        let pfReq <- mkConnection(c.pfRequest, s.pfRequest);
        let resp <- mkConnection(c.response, s.response);
        let newReq <- mkConnection(c.newRequest, s.newRequest);
    endmodule
endinstance

instance Connectable#(CommitPFServer#(a, b), CommitPFClient#(a, b));
    module mkConnection#(CommitPFServer#(a, b) s, CommitPFClient#(a, b) c)(Empty);
        (* hide *)
        let _x <- mkConnection(c, s);
    endmodule
endinstance

// Conversions for standard FIFOs
typeclass ToSendCommit#(type a, type b)
    dependencies (a determines b);
    module mkSendCommit#(a x) (SendCommit#(b));
endtypeclass

typeclass ToRecvCommit#(type a, type b)
    dependencies (a determines b);
    module mkRecvCommit#(a x) (RecvCommit#(b)); 
endtypeclass

// As above, but also takes in a "notification" PulseWire to ping when a 
// new packet is accepted.
// This is currently just used to ping arbiters when a packet has been
// accepted in order to notify of the new packet and perform accounting
// correctly.
typeclass ToRecvCommitPF#(type a, type b)
    dependencies(a determines b);
    module mkRecvCommitPF#(a x, PulseWire notify) (RecvCommit#(b));
endtypeclass

instance ToSendCommit#(FIFO#(a), a);
    module mkSendCommit#(FIFO#(a) f) (SendCommit#(a));
        PulseWire doAck <- mkPulseWire();

        (* fire_when_enabled *)
        rule doDeq(doAck);
            f.deq();
        endrule

        method a dataout;
            return f.first();
        endmethod

        // Don't care about the ack data
        method Action ack(AckType data);
            doAck.send();
        endmethod
    endmodule
endinstance
// Cannot have a ToRecvCommit#(FIFO) because a notFull signal is needed

instance ToSendCommit#(FIFOF#(a), a);
    module mkSendCommit#(FIFOF#(a) f) (SendCommit#(a));
        PulseWire doAck <- mkPulseWire();

        (* fire_when_enabled *)
        rule doDeq(doAck);
            f.deq();
        endrule

        method a dataout;
            return f.first();
        endmethod

        // Don't care about the ack data
        method Action ack(AckType data);
            doAck.send();
        endmethod
    endmodule
endinstance

instance ToRecvCommit#(FIFOF#(a), a)
    provisos(Bits#(a, ba));
    module mkRecvCommit#(FIFOF#(a) f) (RecvCommit#(a));
        RWire#(a) d <- mkRWire();

        (* fire_when_enabled *)
        rule doEnq(d.wget matches tagged Valid .x);
            f.enq(x);
        endrule

        // Datain needs to be always ready, so use a wire
        method Action datain(a din);
            d.wset(din);
        endmethod

        method Maybe#(AckType) accept;
            if(f.notFull && isValid(d.wget))
                return tagged Valid 0;
            else
                return tagged Invalid;
        endmethod
    endmodule
endinstance

// This interface is as above, but when a packet enters the FIFO, it will ping the
// attached PulseWire.
// This is used with the arbiters so we can ping the "newRequest" wire when a new
// packet has been enqueued (and thus is available to the arbiter).
instance ToRecvCommitPF#(FIFOF#(a), a)
    provisos(Bits#(a, ba));
    module mkRecvCommitPF#(FIFOF#(a) f, PulseWire notify) (RecvCommit#(a));
        RWire#(a) d <- mkRWire();

        (* fire_when_enabled *)
        rule doEnq(d.wget matches tagged Valid .x);
            f.enq(x);
            notify.send(); // Predicated on f.enq(). Will only notify when enqueue can happen.
        endrule   

        method Action datain(a din);
            d.wset(din);
        endmethod

        method Maybe#(AckType) accept;
            if(f.notFull() && isValid(d.wget))
                return tagged Valid 0;
            else
                return tagged Invalid;
        endmethod
    endmodule
endinstance

// Don't care about other FIFOs for now...

// Connect to standard Get/Put interfaces
instance ToSendCommit#(Get#(a), a)
    provisos(Bits#(a, ba));

    module mkSendCommit#(Get#(a) g) (SendCommit#(a));
        FIFOF#(a) inter <- mkFIFOF();

        // Connect the FIFO to the standard Get port
        let testConn <- mkConnection(toPut(inter), g);
        SendCommit#(a) sc <- mkSendCommit(inter);

        return sc;
    endmodule
endinstance

instance ToRecvCommit#(Put#(a), a)
    provisos(Bits#(a, ba));

    module mkRecvCommit#(Put#(a) p) (RecvCommit#(a));
        FIFOF#(a) inter <- mkFIFOF();
        let testConn <- mkConnection(toGet(inter), p);
        RecvCommit#(a) rc <- mkRecvCommit(inter);

        return rc;
    endmodule
endinstance

// Connect commit interfaces to normal get/put
instance Connectable#(SendCommit#(a), Put#(a))
   provisos (ToRecvCommit#(Put#(a),a));
   module mkConnection#(SendCommit#(a) sc, Put#(a) p) (Empty);
      RecvCommit#(a) rc <- mkRecvCommit(p);
      let connRCToSC <- mkConnection(rc, sc);
   endmodule
endinstance
instance Connectable#(Put#(a), SendCommit#(a))
   provisos (ToRecvCommit#(Put#(a),a));
   module mkConnection#(Put#(a) p, SendCommit#(a) sc) (Empty);
      (*hide*) let _i <- mkConnection(sc,p);
   endmodule
endinstance

instance Connectable#(RecvCommit#(a), Get#(a))
   provisos (ToSendCommit#(Get#(a),a));
   module mkConnection#(RecvCommit#(a) rc, Get#(a) g) (Empty);
      SendCommit#(a) sc <- mkSendCommit(g);
      let connSCToRC <- mkConnection(rc, sc);
   endmodule
endinstance
instance Connectable#(Get#(a), RecvCommit#(a))
   provisos (ToSendCommit#(Get#(a),a));
   module mkConnection#(Get#(a) g, RecvCommit#(a) rc) (Empty);
      (*hide*) let _i <- mkConnection(rc,g);
   endmodule
endinstance

// Commit interfaces to client/server
instance Connectable #(CommitClient#(req,resp), Server#(req,resp))
   provisos ( Bits#(resp,_x), Bits#(req,_y));
   module mkConnection #(CommitClient#(req,resp) bc, Server#(req,resp) s)(Empty);
      let connBClient_Server_Request <- mkConnection(bc.request, s.request);
      let connBClient_Server_Reponse <- mkConnection(bc.response, s.response);
   endmodule
endinstance
instance Connectable #(Server#(req,resp), CommitClient#(req,resp))
   provisos ( Bits#(resp,_x), Bits#(req,_y));
   module mkConnection #( Server#(req,resp) s, CommitClient#(req,resp) bc)(Empty);
      (*hide*) let _c <- mkConnection(bc,s);
   endmodule
endinstance

instance Connectable #(CommitServer#(req,resp), Client#(req,resp))
   provisos ( Bits#(resp,_x), Bits#(req,_y));
   module mkConnection #(CommitServer#(req,resp) bs, Client#(req,resp) c)(Empty);
      let connBServer_Client_Request <- mkConnection(bs.request, c.request);
      let connBServer_Client_Reponse <- mkConnection(bs.response, c.response);
   endmodule
endinstance
instance Connectable #( Client#(req,resp), CommitServer#(req,resp))
   provisos ( Bits#(resp,_x), Bits#(req,_y));
   module mkConnection #( Client#(req,resp) c, CommitServer#(req,resp) bs)(Empty);
      (*hide*) let _c <- mkConnection(bs,c);
   endmodule
endinstance

// And now for the PF instances
instance Connectable#(CommitPFClient#(req, resp), Server#(req, resp))
  provisos(Bits#(resp, _x), Bits#(req, _y));
  module mkConnection#(CommitPFClient#(req, resp) bc, Server#(req, resp) s)(Empty);
    let connBClient_Server_Request <- mkConnection(bc.request, s.request);
    let connBClient_Server_Reponse <- mkConnection(bc.response, s.response);
    // Leave PF request dangling
    // The server won't care about the newRequest counter...
  endmodule
endinstance
instance Connectable #(Server#(req,resp), CommitPFClient#(req,resp))
   provisos ( Bits#(resp,_x), Bits#(req,_y));
   module mkConnection #( Server#(req,resp) s, CommitPFClient#(req,resp) bc)(Empty);
      (*hide*) let _c <- mkConnection(bc,s);
   endmodule
endinstance

instance Connectable #(CommitPFServer#(req,resp), Client#(req,resp))
   provisos ( Bits#(resp,_x), Bits#(req,_y), 
              ToSendCommit#(FIFOF#(req), req) 
   );
   module mkConnection #(CommitPFServer#(req,resp) bs, Client#(req,resp) c)(Empty);
      // This one is going to be a bit of a pain to connect.
      // We need an intermediate on the request interface in order to correctly send
      // the newRequest counters...
      // Stores packets going up.
      PulseWire notify <- mkPulseWire();          // Notification wire
      RWire#(UInt#(2)) notifyWire <- mkRWire();   // So we can just use toGet...
      FIFOF#(req) reqFifo <- mkFIFOF();           // Actual packets

      RecvCommit#(req) recv <- mkRecvCommitPF(reqFifo, notify);  // Connect using leaky converter
      SendCommit#(req) send <- mkSendCommit(reqFifo);            // Out the other end

      mkConnection(recv, c.request);          // Connect up helpers
      mkConnection(send, bs.request);
      mkConnection(c.response, bs.response);  // And the response path... 

      // PulseWire -> RWire conversion
      rule updateNotifyWire(notify);
          notifyWire.wset(0);
      endrule

      mkConnection(bs.newRequest, toGet(notifyWire));

      // Leave PF interface dangling.
   endmodule
endinstance
instance Connectable #( Client#(req,resp), CommitPFServer#(req,resp))
   provisos ( Bits#(resp,_x), Bits#(req,_y));
   module mkConnection #( Client#(req,resp) c, CommitPFServer#(req,resp) bs)(Empty);
      (*hide*) let _c <- mkConnection(bs,c);
   endmodule
endinstance


// TODO: Make shims to connect up to raw Client/Server interfaces.

// Make Bluetree variants
typedef CommitClient#(BluetreeClientPacket, BluetreeServerPacket) BluetreeCommitClient;
typedef CommitServer#(BluetreeClientPacket, BluetreeServerPacket) BluetreeCommitServer;
typedef CommitPFClient#(BluetreeClientPacket, BluetreeServerPacket) BluetreePFCommitClient;
typedef CommitPFServer#(BluetreeClientPacket, BluetreeServerPacket) BluetreePFCommitServer;

endpackage