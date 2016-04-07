package BluetreeTrafficGenerators2;

export BluetreeTrafficGenerator2(..);
export mkBluetreeFloodTrafficGenerator2;
export mkBluetreeIntervalTrafficGenerator2;
export mkBluetreeRandomTrafficGenerator2;
export mkBluetreeNullTrafficGenerator2;

import Bluetree2::*;
import GetPut::*;
import Connectable::*;
import ClientServer::*;
import PrioritySetReset::*;
import Randomizable::*;

interface BluetreeTrafficGenerator2#(type client_pkt, type server_pkt);
    interface Client#(client_pkt, server_pkt) client;
endinterface

module mkBluetreeFloodTrafficGenerator2#(Bool awaitResponse) (BluetreeTrafficGenerator2#(client_pkt, server_pkt))
    provisos(BluetreeDataContainer#(client_pkt, client_data),
	     Arith#(client_data),
	     Bits#(client_pkt, client_pkt_bits),
	     Bits#(client_data, client_data_bits),
	     Add#(a__, 32, client_data_bits)
	     );
    BluetreeTrafficGenerator2#(client_pkt, server_pkt) tg <- mkBluetreeIntervalTrafficGenerator2(awaitResponse, 0);

    return tg;
endmodule

module mkBluetreeNullTrafficGenerator2(BluetreeTrafficGenerator2#(client_pkt, server_pkt))
    provisos(Bits#(client_pkt, client_pkt_bits));
    interface Client client;
	interface Get request;
	    method ActionValue#(client_pkt) get() if(False);
		return unpack(0);
	    endmethod
	endinterface
	
	interface Put response;
	    method Action put(server_pkt p);
	    endmethod
	endinterface
    endinterface
endmodule

// This is a special one.
// It will emit a packet, then await the response. After receiving the response, it will then wait between minDelay and maxDelay
// cycles before emitting a new one.
// This does not have an awaitResponse parameter, as it will always await the response.
module mkBluetreeRandomTrafficGenerator2#(UInt#(32) minDelay, UInt#(32) maxDelay)(BluetreeTrafficGenerator2#(client_pkt, server_pkt))
    provisos(BluetreeDataContainer#(client_pkt, client_data),
	     Arith#(client_data),
	     Bits#(client_pkt, client_pkt_bits),
	     Bits#(client_data, client_data_bits),
	     Add#(a__, 32, client_data_bits)
    );

    Reg#(Bit#(32)) cycle_counter <- mkReg(0);
    Reg#(UInt#(32)) countdown <- mkReg(0);
    IfcPrioritySR#(Bool) response_pending <- mkPrioritySR(False);
    Randomize#(UInt#(32)) random_gen <- mkConstrainedRandomizer(minDelay, maxDelay);
    Reg#(Bool) inited <- mkReg(False);
    
    rule init(inited == False);
	inited <= True;
	random_gen.cntrl.init();
    endrule
    
    rule cycle_tick;
	cycle_counter <= cycle_counter + 1;
    endrule
    
    rule countdown_tick(countdown != 0 && !response_pending);
	countdown <= countdown - 1;
    endrule
    
    interface Client client;
	interface Get request;
	    method ActionValue#(client_pkt) get() if(countdown == 0 && (!response_pending));
		client_pkt p = unpack(0);
		client_data d = unpack(zeroExtend(pack(cycle_counter)));
		p = setData(p, d);
		response_pending <= True;
	
		// Now need to set the countdown
		let rv <- random_gen.next();
		countdown <= rv;
		
		return p;
	    endmethod
	endinterface
	
	interface Put response;
	    method Action put(server_pkt p);
		response_pending.reset();
	    endmethod
	endinterface
    endinterface
endmodule
    
module mkBluetreeIntervalTrafficGenerator2#(Bool awaitResponse, UInt#(32) delay) (BluetreeTrafficGenerator2#(client_pkt, server_pkt))
    provisos(BluetreeDataContainer#(client_pkt, client_data),
             Arith#(client_data),
             Bits#(client_pkt, client_pkt_bits),
             Bits#(client_data, client_data_bits),
             Add#(a__, 32, client_data_bits)
    );
    
    Reg#(Bit#(32)) cycle_counter <- mkReg(0);
    Reg#(UInt#(32)) countdown <- mkReg(delay);
    IfcPrioritySR#(Bool) response_pending <- mkPrioritySR(False);
    
    rule tick;
       cycle_counter <= cycle_counter + 1;

        if(countdown == 0)
            countdown <= delay;
        else
            countdown <= countdown - 1;
    endrule
    
    interface Client client;
        interface Get request;
	    method ActionValue#(client_pkt) get() if(countdown == 0 && (!awaitResponse || !response_pending));
		// Construct an empty packet...
		client_pkt p = unpack(0);
		
		client_data d = unpack(zeroExtend(pack(cycle_counter)));
            
		p = setData(p, d);
	
		if(awaitResponse)
		    response_pending <= True;
		
		return p;
            endmethod
        endinterface
        
        interface Put response;
            method Action put(server_pkt p);
		response_pending.reset();
            endmethod
        endinterface
    endinterface

endmodule

endpackage