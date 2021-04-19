#pragma once

#include "../tntcxx/src/Buffer/Buffer.hpp"
#include "../tntcxx/src/Client/Connector.hpp"
#include "../tntcxx/src/Client/LibevNetProvider.hpp"
#include "../tntcxx/src/Utils/Mempool.hpp"

#include <string>
#include <map>

#include "config.h"

enum CallMode {
	READ = 0,
	WRITE = 1
};

static constexpr size_t BUFFER_SIZE = 16 * 1024;

using Buf_t = tnt::Buffer<BUFFER_SIZE>;
using BufIter_t = typename Buf_t::iterator;
using Net_t = LibevNetProvider<Buf_t, NetworkEngine>;
//using Net_t = DefaultNetProvider<Buf_t, NetworkEngine>;

class ReplicaSet;
class Router;

class Replica {
public:
	friend Router;
	friend ReplicaSet;
	Replica(Connector<Buf_t, Net_t> &connector, const std::string &name,
		const std::string &uuid, const std::string &address,
		size_t port, size_t weight);
	~Replica() noexcept;
	Replica(Replica &&) = delete;
	Replica(const Replica &) = delete;
	Replica operator = (const Replica&) = delete;
	Replica operator = (Replica&&) = delete;

	void setMaster(Replica *master);
	bool isMaster() const;
	int connect();
	bool isConnected();

	template <class T>
	void callAsync(const std::string &func, const T &args, rid_t *future);
	template <class T>
	int callSync(const std::string &func, const T &args,
		     Response<Buf_t> &result);
	template <class T>
	int callSyncRaw(const std::string &func, const T &args,
			Response<Buf_t> &result);

	std::string toString();
private:
	/** Default timeout in milliseconds. */
	static constexpr size_t DEFAULT_NETWORK_TIMEOUT = 100;
	Connector<Buf_t, Net_t> &m_Connector;
	std::string m_Name;
	std::string m_Uuid;
	std::string m_Address;
	size_t m_Port;
	size_t m_Weight;
	size_t m_Timeout;

	Replica *m_Master;
	Connection<Buf_t, Net_t> m_Connection;
};

class ReplicaSet {
public:
	friend Router;
	ReplicaSet(const std::string &uuid, size_t weight);
	~ReplicaSet() noexcept;
	ReplicaSet(ReplicaSet &&) = delete;
	ReplicaSet(const ReplicaSet &) = delete;
	ReplicaSet operator = (const ReplicaSet&) = delete;
	ReplicaSet operator = (ReplicaSet&&) = delete;

	void setMaster(Replica *master);
	void addReplica(Replica *replica);
	int connect(const std::string_view &uuid);
	int connectAll();
	int connectMaster();
	template <class T>
	int call(const std::string &func, const T &args, Response<Buf_t> &res);
	template <class T>
	int callRaw(const std::string &func, const T &args, Response<Buf_t> &res);

	std::string toString();

	/** Compare replicasets by weights */
	friend bool operator == (const ReplicaSet &lhs, const ReplicaSet &rhs);
	friend bool operator <  (const ReplicaSet &lhs, const ReplicaSet &rhs);
private:
	template <class T>
	int replicaCall(const std::string &uuid, const std::string &func,
			const T &args, Response<Buf_t> &res);
	template <class T>
	int replicaCallRaw(const std::string &uuid, const std::string &func,
			const T &args, Response<Buf_t> &res);

	std::string m_Uuid;
	size_t m_Weight;
	size_t m_BucketCount;
	Replica *m_Master;
	/** uuid --> replica map */
	std::map<std::string, Replica *> m_Replicas;
};


class Router {
public:
	Router(const std::string &name);
	~Router();

	int addReplicaSet(ReplicaSetCfg *replicaSetCfg);
	void removeReplicaSet(ReplicaSet *rs);
	/** Connect all replicasets. */
	void connectAll();

	/** Discovery API */
	ReplicaSet * setBucket(size_t bucket_id, const std::string &rs_uuid);
	void resetBucket(size_t bucket_id);
	ReplicaSet * discoveryBucket(size_t bucket_id);
	int discovery();
	/** Call API */
	int call(size_t bucket_id, const char *args, const char *args_end,
		 size_t args_count, std::vector<box_tuple_t *> &results);

	void reset();
	void setBucketCount(uint32_t bucketCount);
private:
	static constexpr size_t CALL_TIMEOUT = 1;
	/** Name of the router. */
	std::string m_Name;
	size_t m_TotalBucketCount;
	/** bucket_id --> ReplicaSet map */
	std::map<size_t, ReplicaSet *> m_Routes;
	/** uuid --> ReplicaSet map */
	std::map<std::string, ReplicaSet *> m_ReplicaSets;
	Connector<Buf_t, Net_t> m_Connector;

	static constexpr size_t STATIC_TUPLE_BUF_SZ = 1024;
	static char m_TupleBuf[STATIC_TUPLE_BUF_SZ];
};

class StaticRouterHolder {
public:
	static Router& getRouter()
	{
		/* Set the order of static object initialization. It is
		 * required to run mempool constructor BEFORE calling
		 * router's constructor. Otherwise, destructors called in
		 * reverse order may lead to situation when mempool's
		 * dtor is called BEFORE router's dtor - it is unacceptable
		 * since invocation of router's dtor follows by buffer's
		 * dtor, which in turn appeals to mempool.
		 */
		(void) tnt::MempoolInstance<BUFFER_SIZE>::defaultInstance();
		static Router router("static_router");
		return router;
	}
};