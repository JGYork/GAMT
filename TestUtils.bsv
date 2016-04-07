package TestUtils;

export mkMemConsumer2;

import Bluetree2::*;
import FIFO::*;
import ClientServer::*;
import GetPut::*;
import DReg::*;

module mkMemConsumer2#(UInt#(8) acceptInterval)(Server#(client_pkt, server_pkt))
    provisos(BluetreeRoutable#(client_pkt, client_cpu_id),
	     BluetreeRoutable#(server_pkt, client_cpu_id),
	     BluetreeDataContainer#(client_pkt, client_data),
	     Bits#(client_pkt, client_pkt_bits),
	     Bits#(server_pkt, server_pkt_bits),
	     Bits#(client_cpu_id, client_cpu_id_bits),
	     Bits#(client_data, client_data_bits),
	     Add#(_a_, 4, client_cpu_id_bits)
	     );
    Reg#(UInt#(8)) acceptCounter <- mkReg(0); // Zero since the TDM counter is also zero-based, and to
                                              // prevent a dynamic initialiser.
    Reg#(Bit#(32)) cycle_counter <- mkReg(0);
    Reg#(Maybe#(client_pkt)) bouncePkt <- mkDReg(tagged Invalid);
    
    rule tick;
	cycle_counter <= cycle_counter + 1;
    endrule
    
    rule decAcceptCounter;
        if(acceptCounter == 0)
            acceptCounter <= acceptInterval;
        else
            acceptCounter <= acceptCounter - 1;
    endrule

    interface Put request;
        method Action put(client_pkt pkt) if(acceptCounter == 0);
	    client_data data = getData(pkt);
	    client_cpu_id cpu_id = getCpuId(pkt);
	    
	    Bit#(4) cpu_id_trunc = truncate(pack(cpu_id));
	    bouncePkt <= tagged Valid pkt;
            $display("MEMCONSUMER: Putting packet for CPU %d dispatched @ %d received @ %d", unpack(reverseBits(cpu_id_trunc)), data, cycle_counter);
        endmethod
    endinterface

    interface Get response;
        // This will, of course, raise a warning about a constant False enable.
        method ActionValue#(server_pkt) get() if(bouncePkt matches tagged Valid .pkt);
            server_pkt resp_pkt = unpack(0);
	    client_cpu_id cpu_id = getCpuId(pkt);
	    resp_pkt = setCpuId(resp_pkt, cpu_id);
	    
	    return resp_pkt;
        endmethod
    endinterface
endmodule

endpackage