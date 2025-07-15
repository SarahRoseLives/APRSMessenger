import aprslib

packet = aprslib.parse("OURUSER>APRS,K8SDR*,qAC,K8SDR-10::RXUSER   :Hello from from the aprs messenger gateway!")

print(packet)

